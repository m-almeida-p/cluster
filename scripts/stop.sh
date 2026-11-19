#!/usr/bin/env bash
# Stops the cluster, keeping containers and volumes so data survives.
# Usage: ./scripts/stop.sh

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_docker
echo "⏸️   Stopping cluster containers (data preserved)..."
compose stop
