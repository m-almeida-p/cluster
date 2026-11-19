# Yape local cluster

One shared infrastructure stack for the local development of
`ms-ml-ai-gateway-bs`, `ms-ml-genai-agents-bs` and `ms-ml-agents-bff`.

Before this existed, each repo shipped its own `local/docker-compose.yml` that
started its own Kafka, Zookeeper, Redis and Schema Registry. Running two repos at
once was not possible, and — more insidiously — running them *sequentially* broke
them (see [Why this exists](#why-this-exists)).

## Quick start

```bash
./scripts/up.sh        # start everything and print a status report
./scripts/status.sh    # what is exposed, and does it actually answer
./scripts/stop.sh      # stop containers, keep data
./scripts/down.sh      # remove containers, keep volumes
./scripts/clean.sh     # remove containers AND volumes (destructive)
./scripts/logs.sh kafka    # follow one service, or all of them
```

The cluster runs as the compose project **`yape-cluster`** on the network
**`yape-local`**. Repos attach to that network as `external: true`.

## What it runs

| Service | Host port | Container address | Notes |
|---|---|---|---|
| Redis | 6379 | `redis:6379` | password `debug` |
| Postgres | 5432 | `db:5432` | user `postgres`, trust auth (local only), `wal_level=logical` for Debezium |
| Zookeeper | 2181 | `zookeeper:2181` | |
| Kafka | 9092 | `kafka:29092` | see [Two listeners](#two-listeners-and-why-it-matters) |
| Schema Registry | **8085** | `schema-registry:8081` | host port moved, see below |
| REST Proxy | 8082 | `rest-proxy:8082` | |
| Kafka Connect | 8083 | `connect:8083` | REST API for connectors, Debezium PostgreSQL plugin installed on start. The connectors live in `ms-ml-conv-history-publisher` |
| Kafka UI | 8090 | — | <http://localhost:8090> |
| RedisInsight | 8001 | — | <http://localhost:8001> |
| Unleash | 4242 | `unleash:4242` | `admin` / `unleash4all` |
| OTLP (gRPC / HTTP) | 4317 / 4318 | `otel-collector:4317` | |
| Jaeger UI | 16686 | — | <http://localhost:16686> |
| `init-kafka` | — | — | one-shot topic creator, exits 0 |

Ports are set in `.env`. Change them there, never in `docker-compose.yml`.

### Data persistence

Kafka, Zookeeper, Redis, Postgres and RedisInsight all write to named volumes, so
`stop.sh` and `down.sh` preserve state — including registered schemas, which live
in the Kafka `_schemas` topic. Only `clean.sh` destroys data.

Postgres is version 18. Its image keeps the data in a version folder under
`/var/lib/postgresql`, so the `postgres18_data` volume is mounted there, not at
`/var/lib/postgresql/data` as in older images. A data directory of another major
version cannot be opened by it: moving to the next major version means a dump and
restore, or a new volume.

This is easy to get wrong: without a volume on the broker's log directory, topics
still *appear* to survive a `down.sh` because `init-kafka` recreates them on the
next `up.sh`, while every message — and every registered subject — is silently
gone.

### Schema Registry is on 8085, not 8081

8081 is the Confluent default, but it collides with other local services. The
**container** port is still 8081, which matters because the repo bootstrap
scripts hardcode `http://schema-registry:8081` and cannot be configured. Only the
host mapping moved.

If you connect from the host (for example a gateway started with
`scripts/run_gateway.sh`), use `http://127.0.0.1:8085`.

## Creating Kafka topics

Topics live in **one place**: `KAFKA_CREATE_TOPICS` in `.env`, using the
`name:partitions:replicas` format borrowed from `wurstmeister/kafka`.

```bash
KAFKA_CREATE_TOPICS=ai-gateway-logs:1:1,data.payments.transaction.filter:1:1
```

The `init-kafka` sidecar parses that and creates each topic with
`--if-not-exists`, so re-running is safe. It waits for the broker to be healthy
and exits 0 on success; `up.sh` fails loudly if it exits non-zero.

> `KAFKA_CREATE_TOPICS` is a `wurstmeister/kafka` feature, not a Confluent one.
> We kept the familiar format but implemented it ourselves, because
> `wurstmeister/kafka` has not been rebuilt since 2022 and ships Kafka 2.8.1.

To add a topic: edit `.env`, then `docker compose up -d init-kafka`.

**Debezium topics are the exception.** A connector creates its own topic, with the partitions its config asks for
(`topic.creation.default.partitions`), so they are not in `KAFKA_CREATE_TOPICS`. The topic of the conversation events,
`yape.event_store.conversation_events`, is created by the connector in `ms-ml-conv-history-publisher`.

## Two listeners, and why it matters

Kafka advertises two addresses:

- `PLAINTEXT://kafka:29092` — for other **containers**
- `PLAINTEXT_HOST://localhost:9092` — for processes on the **host**

A service running on your laptop (the gateway via `make run` or
`scripts/run_gateway.sh`) must use `localhost:9092`. A service running as a
container must use `kafka:29092`. Using the wrong one produces a connection that
appears to open and then fails on metadata, because the broker hands back an
address the client cannot resolve.

## Registering a JSON schema

The gateway publishes to `ai-gateway-logs` and its Kafka client runs with
`AutoRegisterSchemas = false`, so the schema must exist *before* the first
publish or the producer logs `ai-gateway-logs-value schema not registered`.

```bash
cd ../ms-ml-ai-gateway-bs
jq -Rs '{schemaType:"JSON", schema:.}' < schemas/gateway-event-schema.json \
  | curl -s -X POST http://localhost:8085/subjects/ai-gateway-logs-value/versions \
      -H "Content-Type: application/vnd.schemaregistry.v1+json" -d @-
```

Subject naming follows the Kafka convention `<topic>-value`.

## Why this exists

Compose derives the project name from the **directory**, not the repository. Both
`ms-ml-ai-gateway-bs/local/` and `ms-ml-genai-agents-bs/local/` resolved to the
project `local`, which meant:

- Both built an image tagged `local-local-bootstraper:latest`, and whichever repo
  ran second silently reused the **other repo's** image, because
  `docker compose up` does not rebuild an image that already exists.
- `docker compose ls` showed a single `local` project owning the config files of
  both repos, so `docker compose down` in one repo tore down the other.
- Fixed `container_name` values (`kafka`, `zookeeper`, `schema-registry`,
  `rest-proxy`) made coexistence impossible anyway.

The failure was hard to spot: the bootstrap `command:` separates two steps with a
newline instead of `&&`, so a crash in the first step is swallowed. The container
reported `running`, uvicorn kept the port open, and only `curl` returning nothing
revealed that the worker had died with `ModuleNotFoundError: No module named
'confluent_kafka'` — a module the Dockerfile does install, just not in the stale
image that got reused.

This cluster owns the infrastructure; each repo keeps only its own application
services in `local-1/`, under a project named after the repo.

## Per-repo services

The original `local/` folders are left untouched. Each repo has a parallel
`local-1/` (git-ignored) with only its app-specific services, attached to
`yape-local`:

| Repo | Service | Port |
|---|---|---|
| `ms-ml-ai-gateway-bs` | `bootstraper` | 8888 |
| `ms-ml-genai-agents-bs` | `bootstraper` / `agui-bff` | 8889 / 4000 |
| `ms-ml-agents-bff` | `agui-web` | 4001 |

```bash
cd ../ms-ml-ai-gateway-bs/local-1 && docker compose up -d
```

`ms-ml-agents-bff` expects `local/agui-web/.env`, which is not in the repo. Copy
it from the example before starting that service:

```bash
cp ../ms-ml-agents-bff/local/agui-web/.env.example \
   ../ms-ml-agents-bff/local/agui-web/.env
```

The compose file marks the env file `required: false`, so validation passes
without it, but the app will run with no configuration.

## Troubleshooting

**A port says `BUSY` in `status.sh`.** Something answers on the port but not as
the expected service — usually an unrelated local process. `status.sh` probes a
known HTTP path precisely to catch this, because `nc -z` only proves that *some*
process holds the port. Find the owner with:

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN
```

**A stale container from the old `local` project.** Check for projects that are
not `yape-cluster`:

```bash
docker compose ls
```

**Topics missing after a `clean.sh`.** Volumes were removed, so recreate them:

```bash
docker compose up -d init-kafka
```

Schemas are not recreated automatically — re-register them (see
[Registering a JSON schema](#registering-a-json-schema)).

**`down.sh` says the network is still in use.** Another project's containers are
attached. The script names them; stop those projects first:

```bash
cd <repo>/local-1 && docker compose down
```
