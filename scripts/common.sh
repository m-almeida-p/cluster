#!/usr/bin/env bash
# Shared helpers for the cluster scripts. Sourced, not executed.

set -euo pipefail

CLUSTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${CLUSTER_DIR}/docker-compose.yml"

compose() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

require_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "❌  Docker is not running." >&2
    exit 1
  fi
}
