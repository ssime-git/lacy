#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${LACY_DOCKER_COMPOSE_FILE:-$REPO_DIR/docker-compose.dev.yml}"

exec docker compose -f "$COMPOSE_FILE" run --rm lacy-dev
