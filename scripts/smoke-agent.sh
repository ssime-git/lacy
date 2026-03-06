#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_HOME="${LACY_SMOKE_HOME:-/tmp/lacy-smoke-home}"
LACY_HOME="$DEV_HOME/.lacy"
FAKE_AGENT="$REPO_DIR/scripts/fake-agent.sh"

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
rm -f "$LACY_HOME/conversation.log"

run_smoke() {
    env \
        HOME="$DEV_HOME" \
        ZDOTDIR="$DEV_HOME" \
        LACY_SHELL_HOME="$LACY_HOME" \
        LACY_AUTO_START=true \
        zsh -i -c "source '$REPO_DIR/lacy.plugin.zsh'; lacy_shell_activate >/dev/null 2>&1 || true; lacy_shell_query_agent 'inspect @README.md and @lib/core'"
}

if [[ "${1:-}" == "--inner" ]]; then
    run_smoke
    exit $?
fi

if command -v script >/dev/null 2>&1; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        exec script -q /dev/null bash -lc "cd '$REPO_DIR' && ./scripts/smoke-agent.sh --inner"
    else
        exec script -qec "cd '$REPO_DIR' && ./scripts/smoke-agent.sh --inner" /dev/null
    fi
fi

run_smoke
