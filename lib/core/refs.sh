#!/usr/bin/env bash

# Shared @reference parsing for completion and query expansion.
# Shared across Bash 4+ and ZSH.

lacy_ref_unescape_path() {
    local value="$1"
    if command -v python3 >/dev/null 2>&1; then
        LACY_REF_VALUE="$value" python3 - <<'PY'
import os

value = os.environ.get("LACY_REF_VALUE", "")
out = []
escape = False
for ch in value:
    if escape:
        out.append(ch)
        escape = False
    elif ch == "\\":
        escape = True
    else:
        out.append(ch)
if escape:
    out.append("\\")
print("".join(out))
PY
        return
    fi

    printf '%s' "$value" | sed 's/\\ / /g; s/\\"/"/g; s/\\\\/\\/g'
}

lacy_ref_escape_path() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value// /\\ }"
    value="${value//\'/\\\'}"
    value="${value//\"/\\\"}"

    printf '%s' "$value"
}

lacy_ref_scan() {
    local query="$1"

    if command -v python3 >/dev/null 2>&1; then
        LACY_REF_QUERY="$query" python3 - <<'PY'
import os
import string

query = os.environ.get("LACY_REF_QUERY", "")
allowed_prev = set("([{'\"")
trim_chars = ",.:;!?"

def should_start(idx):
    if idx == 0:
        return True
    prev = query[idx - 1]
    return prev.isspace() or prev in allowed_prev

def unescape(text):
    out = []
    escape = False
    for ch in text:
        if escape:
            out.append(ch)
            escape = False
        elif ch == "\\":
            escape = True
        else:
            out.append(ch)
    if escape:
        out.append("\\")
    return "".join(out)

i = 0
n = len(query)
while i < n:
    if query[i] != "@" or not should_start(i):
        i += 1
        continue

    start = i
    i += 1
    if i >= n:
        continue

    quoted = False
    quote = ""
    raw = ""
    path = ""

    if query[i] in ("'", '"'):
        quoted = True
        quote = query[i]
        i += 1
        buf = []
        escaped = False
        while i < n:
            ch = query[i]
            if escaped:
                buf.append(ch)
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                i += 1
                break
            else:
                buf.append(ch)
            i += 1
        path = "".join(buf)
        raw = "@" + quote + "".join(buf) + quote
        end = i
    else:
        buf = []
        escaped = False
        while i < n:
            ch = query[i]
            if escaped:
                buf.append(ch)
                escaped = False
                i += 1
                continue
            if ch == "\\":
                escaped = True
                buf.append(ch)
                i += 1
                continue
            if ch.isspace():
                break
            buf.append(ch)
            i += 1
        raw_body = "".join(buf)
        while raw_body and raw_body[-1] in trim_chars and (len(raw_body) < 2 or raw_body[-2] != "\\"):
            raw_body = raw_body[:-1]
            i -= 1
        if not raw_body:
            continue
        raw = "@" + raw_body
        path = unescape(raw_body)
        end = i

    if not path:
        continue

    print(f"{start + 1}\t{end}\t{raw}\t{path}")
PY
        return
    fi

    local tmp="$query"
    while [[ "$tmp" == *"@"* ]]; do
        tmp="${tmp#*@}"
        local token="${tmp%%[[:space:]]*}"
        [[ -z "$token" ]] && continue
        printf '1\t%d\t@%s\t%s\n' "${#token}" "$token" "${token#@}"
        tmp="${tmp#"$token"}"
    done
}

lacy_ref_token_at_cursor() {
    local query="$1"
    local cursor="$2"
    local match=""
    local start end raw path line

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$LACY_SHELL_TYPE" == "zsh" ]]; then
            local -a parts
            parts=( ${(ps:\t:)line} )
            start="${parts[1]}"
            end="${parts[2]}"
            raw="${parts[3]}"
            path="${parts[4]}"
        else
            IFS=$'\t' read -r start end raw path <<< "$line"
        fi
        [[ -z "$start" ]] && continue
        if (( cursor >= start && cursor <= end )); then
            printf '%s\t%s\t%s\t%s\n' "$start" "$end" "$raw" "$path"
            return 0
        fi
        if (( cursor == end + 1 )); then
            match="$(printf '%s\t%s\t%s\t%s' "$start" "$end" "$raw" "$path")"
        fi
    done < <(lacy_ref_scan "$query")

    [[ -n "$match" ]] || return 1
    printf '%s\n' "$match"
}
