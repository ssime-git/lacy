#!/usr/bin/env bash

set -euo pipefail

query="${1:-}"
preview="$(printf '%s\n' "$query" | sed -n '1,20p')"

printf '<thinking>checking prompt</thinking>\n'
printf 'Agent: fake\n'

if [[ "$query" == *"[Lacy referenced paths]"* ]]; then
    printf 'References detected.\n'
fi

printf -- '- [ ] inspect request\n'
printf -- '- [x] fake agent ready\n'
printf '\n'
printf 'Query preview:\n'
printf '%s\n' "$preview"
