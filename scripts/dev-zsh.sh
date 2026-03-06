#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_HOME="${LACY_DEV_HOME:-/tmp/lacy-test-home}"
DEV_LACY_HOME="${LACY_SHELL_HOME:-$DEV_HOME/.lacy}"
DEFAULT_TOOL="${LACY_DEV_TOOL:-opencode}"
CUSTOM_TOOL_CMD="${LACY_DEV_CUSTOM_COMMAND:-}"

mkdir -p "$DEV_HOME" "$DEV_LACY_HOME"

cat > "$DEV_LACY_HOME/config.yaml" <<EOF
agent_tools:
  active: ${DEFAULT_TOOL}
EOF

if [[ "$DEFAULT_TOOL" == "custom" && -n "$CUSTOM_TOOL_CMD" ]]; then
    cat >> "$DEV_LACY_HOME/config.yaml" <<EOF
  custom_command: "${CUSTOM_TOOL_CMD}"
EOF
fi

cat >> "$DEV_LACY_HOME/config.yaml" <<EOF

modes:
  default: auto

agent:
  history_context: false
  show_processing_steps: true
EOF

printf 'auto\n' > "$DEV_LACY_HOME/current_mode"
rm -f \
    "$DEV_LACY_HOME/.server.pid" \
    "$DEV_LACY_HOME/.server_session_id" \
    "$DEV_LACY_HOME/.claude_session_id" \
    "$DEV_LACY_HOME/conversation.log"

cat > "$DEV_HOME/.zshrc" <<EOF
export LACY_SHELL_HOME="$DEV_LACY_HOME"
export LACY_AUTO_START=true
source "$REPO_DIR/lacy.plugin.zsh"
if typeset -f lacy_shell_activate >/dev/null 2>&1; then
    lacy_shell_activate
fi
EOF

echo "Repo:      $REPO_DIR"
echo "Test HOME: $DEV_HOME"
echo "Lacy home: $DEV_LACY_HOME"
echo "Tool:      $DEFAULT_TOOL"
echo ""
echo "This shell uses the repo plugin, not ~/.lacy."
echo "Exit with: exit"
echo ""

exec env \
    HOME="$DEV_HOME" \
    ZDOTDIR="$DEV_HOME" \
    LACY_SHELL_HOME="$DEV_LACY_HOME" \
    LACY_AUTO_START=true \
    zsh -i
