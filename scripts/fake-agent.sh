#!/usr/bin/env bash

set -euo pipefail

query="${1:-}"
original_query="$(printf '%s\n' "$query" | awk 'NF { line=$0 } END { print line }')"
refs="$(printf '%s\n' "$query" | sed -n 's/^- \(FILE\|DIRECTORY\) @/@/p')"

cat <<'EOF'
<thinking>checking prompt
resolving references
building deterministic response</thinking>
EOF
printf 'Agent: fake\n'

if [[ -n "$refs" ]]; then
    printf 'References detected.\n'
    printf 'Referenced paths:\n'
    printf '%s\n' "$refs"
fi

printf -- '- [ ] inspect request\n'
printf -- '- [x] fake agent ready\n'
printf '\n'
printf 'Original query:\n'
printf '%s\n' "$original_query"
