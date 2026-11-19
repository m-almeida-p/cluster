#!/usr/bin/env bash
# Shows what the cluster exposes and whether the ports answer, so a repo can be
# pointed at it with confidence.
# Usage: ./scripts/status.sh

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_docker

echo
echo "📦  Containers"
compose ps --format '   {{.Name}}\t{{.State}}\t{{.Status}}' 2>/dev/null || true

echo
echo "🔌  Endpoints"
# nc -z only proves that something holds the port, which silently passes when an
# unrelated local process squats on it. Where a service speaks HTTP we also probe
# a known path so the check fails loudly on a foreign listener.
check() {
  local label="$1" host="$2" port="$3" note="${4:-}" probe="${5:-}"
  printf '   %-18s %-22s ' "${label}" "${host}:${port}"
  if ! nc -z "${host}" "${port}" >/dev/null 2>&1; then
    printf 'DOWN %s\n' "${note}"
    return
  fi
  if [[ -n "${probe}" ]]; then
    if curl -fsS --max-time 3 "http://${host}:${port}${probe}" >/dev/null 2>&1; then
      printf 'UP   %s\n' "${note}"
    else
      printf 'BUSY %s\n' "port answers but not as this service — another process may hold it"
    fi
    return
  fi
  printf 'UP   %s\n' "${note}"
}

check "Redis"          localhost "${REDIS_PORT:-6379}"            "password: debug"
check "Postgres"       localhost "${POSTGRES_PORT:-5432}"         "user: postgres"
check "Kafka"          localhost "${KAFKA_PORT:-9092}"            "containers use kafka:29092"
check "Schema Registry" localhost "${SCHEMA_REGISTRY_PORT:-8085}" "" "/subjects"
check "REST Proxy"     localhost "${REST_PROXY_PORT:-8082}"       "" "/topics"
check "Kafka Connect" localhost "${CONNECT_PORT:-8083}"         "" "/connectors"
check "Kafka UI"       localhost "${KAFKA_UI_PORT:-8090}"         "http://localhost:${KAFKA_UI_PORT:-8090}" "/"
check "RedisInsight"   localhost "${REDISINSIGHT_PORT:-8001}"     "http://localhost:${REDISINSIGHT_PORT:-8001}"
check "Unleash"        localhost "${UNLEASH_PORT:-4242}"          "admin / unleash4all" "/health"
check "OTLP http"      localhost "${OTLP_HTTP_PORT:-4318}"        ""
check "Jaeger UI"      localhost "${JAEGER_UI_PORT:-16686}"       "http://localhost:${JAEGER_UI_PORT:-16686}" "/"

echo
echo "📇  Kafka topics"
docker exec yape-kafka kafka-topics --bootstrap-server localhost:29092 --list 2>/dev/null \
  | sed 's/^/   /' || echo "   (broker unavailable)"
echo
