#!/usr/bin/env bash

set -euo pipefail

query="${1:-}"
original_query="$(printf '%s\n' "$query" | awk 'NF { line=$0 } END { print line }')"
refs="$(printf '%s\n' "$query" | sed -n 's/^- \(FILE\|DIRECTORY\) @/@/p')"

printf 'LACY_EVENT\tstatus\tchecking prompt\n'
printf 'LACY_EVENT\tthinking_start\n'
printf 'LACY_EVENT\tthinking_delta\tchecking prompt\n'
printf 'LACY_EVENT\tthinking_delta\tresolving references\n'
printf 'LACY_EVENT\tthinking_delta\tbuilding deterministic response\n'
printf 'LACY_EVENT\tthinking_end\n'
printf 'LACY_EVENT\tfinal_text\tAgent: fake\n'

if [[ -n "$refs" ]]; then
    printf 'LACY_EVENT\taction_start\treferences\tlisting resolved paths\n'
    printf 'LACY_EVENT\tfinal_text\tReferences detected.\n'
    printf 'LACY_EVENT\tfinal_text\tReferenced paths:\n'
    while IFS= read -r ref; do
        printf 'LACY_EVENT\tfinal_text\t%s\n' "$ref"
    done <<< "$refs"
    printf 'LACY_EVENT\taction_result\treferences\tok\tresolved paths listed\n'
fi

printf 'LACY_EVENT\ttodo_item\tunchecked\tinspect request\n'
printf 'LACY_EVENT\ttodo_item\tchecked\tfake agent ready\n'
printf 'LACY_EVENT\tfinal_text\t\n'
printf 'LACY_EVENT\tfinal_text\tOriginal query:\n'
printf 'LACY_EVENT\tfinal_text\t%s\n' "$original_query"
