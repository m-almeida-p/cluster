#!/usr/bin/env bash
# Removes containers AND volumes: Postgres data, RedisInsight state and every
# Kafka topic are destroyed. The next up.sh starts from zero.
# Usage: ./scripts/clean.sh [--yes]

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_docker

if [ "${1:-}" != "--yes" ]; then
  read -r -p "⚠️   This deletes all cluster volumes and data. Continue? [y/N] " answer
  case "${answer}" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo "🧹  Removing containers and volumes..."
compose down -v
