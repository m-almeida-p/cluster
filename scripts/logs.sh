#!/usr/bin/env bash
# Tails cluster logs, or follows one service.
# Usage: ./scripts/logs.sh [service] [--dump]
#   service   Limit output to a single service (e.g. kafka)
#   --dump    Write a timestamped file instead of streaming

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_docker

SERVICE=""
DUMP=false
for arg in "$@"; do
  case "${arg}" in
    --dump) DUMP=true ;;
    *) SERVICE="${arg}" ;;
  esac
done

if [ "${DUMP}" = true ]; then
  OUT="${CLUSTER_DIR}/logs_$(date +%Y%m%d_%H%M%S).txt"
  compose logs ${SERVICE:+"${SERVICE}"} > "${OUT}"
  echo "📄  Logs written to ${OUT}"
else
  compose logs -f --tail=100 ${SERVICE:+"${SERVICE}"}
fi
