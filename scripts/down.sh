#!/usr/bin/env bash
# Removes the cluster containers and network, keeping volumes.
# Repo composes join the yape-local network, so stop those first or they will
# be left pointing at a network that no longer exists.
# Usage: ./scripts/down.sh

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_docker
echo "🛑  Removing cluster containers (volumes preserved)..."
compose down

# Compose reports "Resource is still in use" and exits 0 when another project's
# containers are attached to yape-local. Surface the actual blockers, because the
# raw message does not say who is holding the network.
if docker network inspect "yape-local" >/dev/null 2>&1; then
  attached=$(docker network inspect "yape-local" \
    --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
  if [[ -n "${attached// /}" ]]; then
    echo
    echo "⚠️   Network yape-local was kept: still attached to ${attached}"
    echo "    Stop those first, e.g. cd <repo>/local-1 && docker compose down"
  fi
fi
