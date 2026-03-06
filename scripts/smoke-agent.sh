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
        LACY_AUTO_START=false \
        LACY_AGENT_IO_MODE=non-interactive-safe \
        zsh -i -c "source '$REPO_DIR/lacy.plugin.zsh'; lacy_shell_activate; lacy_shell_query_agent 'inspect @README.md and @lib/core'"
}

output="$(run_smoke 2>&1)"
status=$?

printf '%s\n' "$output"

[[ $status -eq 0 ]] || {
    echo "Smoke failed: agent query returned $status" >&2
    exit $status
}

printf '%s' "$output" | grep -q "Thinking" || { echo "Missing thinking block" >&2; exit 1; }
printf '%s' "$output" | grep -q "☐ inspect request" || { echo "Missing unchecked TODO" >&2; exit 1; }
printf '%s' "$output" | grep -q "☑ fake agent ready" || { echo "Missing checked TODO" >&2; exit 1; }
printf '%s' "$output" | grep -q "@README.md" || { echo "Missing file reference" >&2; exit 1; }
printf '%s' "$output" | grep -q "@lib/core" || { echo "Missing directory reference" >&2; exit 1; }
printf '%s' "$output" | grep -q "Original query:" || { echo "Missing final text" >&2; exit 1; }
