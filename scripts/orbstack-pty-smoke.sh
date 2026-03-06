#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_HOME="${LACY_PTY_HOME:-/tmp/lacy-orbstack-home}"
LACY_HOME="$DEV_HOME/.lacy"
FAKE_AGENT="${LACY_PTY_AGENT:-$REPO_DIR/scripts/fake-agent.sh}"

mkdir -p "$DEV_HOME" "$LACY_HOME"

cat > "$LACY_HOME/config.yaml" <<EOF
agent_tools:
  active: custom
  custom_command: "$FAKE_AGENT"

modes:
  default: auto

agent:
  history_context: false
  show_processing_steps: true
EOF

printf 'auto\n' > "$LACY_HOME/current_mode"

cat > "$DEV_HOME/.zshrc" <<EOF
export LACY_SHELL_HOME="$LACY_HOME"
export LACY_AUTO_START=true
source "$REPO_DIR/lacy.plugin.zsh"
EOF

exec env \
    LACY_PTY_REPO="$REPO_DIR" \
    LACY_PTY_HOME="$DEV_HOME" \
    python3 "$REPO_DIR/scripts/pty-smoke.py"
