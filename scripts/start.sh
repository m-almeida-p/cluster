#!/usr/bin/env bash
# Starts containers that already exist, without recreating them.
# Usage: ./scripts/start.sh

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_docker
echo "▶️   Starting existing cluster containers..."
compose start
