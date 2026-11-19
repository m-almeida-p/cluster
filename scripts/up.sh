#!/usr/bin/env bash
# Creates and starts the shared infrastructure, then waits for the pieces the
# repos depend on. Safe to re-run: topics are created --if-not-exists.
# Usage: ./scripts/up.sh [--build]

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_docker

BUILD_ARGS=()
if [ "${1:-}" = "--build" ]; then
  BUILD_ARGS+=(--build)
fi

echo "🚀  Starting the shared cluster..."
# Bash 3.2 (the macOS default) treats an empty array expansion as unset, so the
# expansion has to be guarded even though BUILD_ARGS is always declared.
compose up -d ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}

# init-kafka is a one-shot container; its exit status is the signal that the
# topic list in .env was applied.
echo "⏳  Waiting for topic creation..."
for _ in $(seq 1 30); do
  STATUS="$(docker inspect yape-init-kafka --format '{{.State.Status}}' 2>/dev/null || echo missing)"
  if [ "${STATUS}" = "exited" ]; then break; fi
  sleep 2
done

EXIT_CODE="$(docker inspect yape-init-kafka --format '{{.State.ExitCode}}' 2>/dev/null || echo 1)"
if [ "${EXIT_CODE}" != "0" ]; then
  echo "❌  Topic creation failed. Logs:" >&2
  docker logs yape-init-kafka 2>&1 | tail -20 >&2
  exit 1
fi

echo "✅  Cluster is up."
"$(dirname "${BASH_SOURCE[0]}")/status.sh"
