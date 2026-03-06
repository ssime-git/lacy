#!/usr/bin/env bash

# Shell execution history capture + query enrichment for Lacy Shell.
# Shared across Bash 4+ and ZSH.

# Last command captured by preexec (ZSH) or precmd (Bash)
LACY_LAST_CMD=""

# Populated by lacy_expand_references and read by mcp.sh
LACY_EXPANDED_REFS=()

lacy_history_log() {
    local cmd="$1"
    local exit_code="${2:-0}"

    [[ -z "$cmd" ]] && return
    [[ -z "$LACY_SHELL_CONVERSATION_FILE" ]] && return
    [[ "$cmd" == lacy_* || "$cmd" == _lacy_* ]] && return

    local timestamp
    timestamp=$(date +%H:%M:%S 2>/dev/null) || timestamp=""

    {
        printf 'CMD: %s\n' "$cmd"
        printf 'EXIT: %s\n' "$exit_code"
        [[ -n "$timestamp" ]] && printf 'TS: %s\n' "$timestamp"
        printf -- '---\n'
    } >> "$LACY_SHELL_CONVERSATION_FILE"
}

lacy_redact_sensitive_text() {
    local value="$1"

    value=$(printf '%s' "$value" | sed -E \
        -e 's#([A-Za-z][A-Za-z0-9_]*(TOKEN|KEY|SECRET|PASS|PASSWORD|COOKIE|AUTH)[A-Za-z0-9_]*=)[^[:space:]]+#\1[REDACTED]#Ig' \
        -e 's#(https?://[^/@[:space:]]+:)[^@/[:space:]]+@#\1[REDACTED]@#g' \
        -e 's#([?&](access_token|token|api_key|apikey|password|passwd|secret)=)[^&[:space:]]+#\1[REDACTED]#Ig' \
        -e 's#(Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[^"[:space:]]+#\1[REDACTED]#Ig' \
        -e "s#(Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[^'[:space:]]+#\\1[REDACTED]#Ig" \
        -e 's#(--header[=[:space:]]+["'"'"']?Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[^"'"'"'"[:space:]]+#\1[REDACTED]#Ig' \
        -e 's#(-u[[:space:]]+[^:[:space:]]+:)[^[:space:]]+#\1[REDACTED]#g')

    printf '%s' "$value"
}

lacy_history_should_include_context() {
    [[ "${LACY_AGENT_INCLUDE_HISTORY:-false}" == "true" ]]
}

lacy_build_context_query() {
    local query="$1"
    local max_entries="${LACY_HISTORY_MAX_ENTRIES:-5}"

    if ! lacy_history_should_include_context; then
        printf '%s' "$query"
        return
    fi

    if [[ ! -f "$LACY_SHELL_CONVERSATION_FILE" ]]; then
        printf '%s' "$query"
        return
    fi

    local raw
    raw=$(tail -n $(( max_entries * 4 )) "$LACY_SHELL_CONVERSATION_FILE" 2>/dev/null)
    [[ -z "$raw" ]] && {
        printf '%s' "$query"
        return
    }

    local context="" line cmd="" exit_code=""
    while IFS= read -r line; do
        case "$line" in
            "CMD: "*) cmd="${line#CMD: }" ;;
            "EXIT: "*) exit_code="${line#EXIT: }" ;;
            ---)
                if [[ -n "$cmd" ]]; then
                    cmd=$(lacy_redact_sensitive_text "$cmd")
                    context+="  - ${cmd}"
                    [[ -n "$exit_code" && "$exit_code" != "0" ]] && context+=" (exit ${exit_code})"
                    context+=$'\n'
                fi
                cmd=""
                exit_code=""
                ;;
        esac
    done <<< "$raw"

    if [[ -z "$context" ]]; then
        printf '%s' "$query"
        return
    fi

    printf '%s\n%s\n%s\n\n%s' \
        "[Lacy shell context]" \
        "Recent shell commands (redacted):" \
        "${context%$'\n'}" \
        "$query"
}

lacy_is_safe_ref_path() {
    local ref_path="$1"

    [[ -z "$ref_path" ]] && return 1
    [[ "$ref_path" == /* ]] && return 1
    [[ "$ref_path" == ~* ]] && return 1
    [[ "$ref_path" == *".."* ]] && return 1
    return 0
}

lacy_is_text_file() {
    local ref_path="$1"

    [[ ! -f "$ref_path" || ! -r "$ref_path" ]] && return 1
    [[ ! -s "$ref_path" ]] && return 0
    LC_ALL=C grep -Iq . "$ref_path" 2>/dev/null
}

lacy_append_reference_note() {
    local note="$1"
    LACY_EXPANDED_REFS+=("$note")
}

lacy_append_file_reference() {
    local result_var="$1"
    local ref_path="$2"
    local label="${3:-$ref_path}"
    local contents
    contents=$(head -c "${LACY_REF_MAX_BYTES:-8192}" "$ref_path" 2>/dev/null)

    printf -v "$result_var" '%s\n%s\n```text\n%s\n```\n' \
        "${!result_var}" \
        "- FILE @${label}" \
        "$contents"
}

lacy_collect_directory_entries() {
    local ref_path="$1"
    local max_depth="${LACY_REF_DIR_MAX_DEPTH:-3}"
    local max_listing="${LACY_REF_DIR_MAX_LISTING:-40}"

    find "$ref_path" -mindepth 1 -maxdepth "$max_depth" | LC_ALL=C sort | head -n "$max_listing"
}

lacy_expand_references() {
    local query="$1"
    local refs_block=""
    local seen=":"
    local tmp="$query"
    LACY_EXPANDED_REFS=()

    while [[ "$tmp" == *"@"* ]]; do
        tmp="${tmp#*@}"
        local token="${tmp%%[[:space:]]*}"
        tmp="${tmp#"$token"}"

        [[ -z "$token" ]] && continue

        local ref_path="$token"
        while [[ -n "$ref_path" ]]; do
            case "${ref_path: -1}" in
                ','|'.'|':'|';'|'!'|'?') ref_path="${ref_path%?}" ;;
                *) break ;;
            esac
        done

        lacy_is_safe_ref_path "$ref_path" || continue
        [[ -e "$ref_path" ]] || continue
        [[ "$seen" == *":${ref_path}:"* ]] && continue
        seen+=":${ref_path}:"

        if [[ -f "$ref_path" && -r "$ref_path" ]]; then
            lacy_append_reference_note "file:${ref_path}"
            refs_block+=$'\n'"- FILE @${ref_path}"$'\n'
            refs_block+="\`\`\`text"$'\n'
            refs_block+="$(head -c "${LACY_REF_MAX_BYTES:-8192}" "$ref_path" 2>/dev/null)"$'\n'
            refs_block+="\`\`\`"$'\n'
            continue
        fi

        if [[ -d "$ref_path" && -r "$ref_path" ]]; then
            lacy_append_reference_note "dir:${ref_path}"
            refs_block+=$'\n'"- DIRECTORY @${ref_path}"$'\n'
            refs_block+="Entries:"$'\n'

            local listing_count=0
            local entry
            while IFS= read -r entry; do
                [[ -z "$entry" ]] && continue
                entry="${entry#./}"
                refs_block+="  - ${entry}"$'\n'
                listing_count=$(( listing_count + 1 ))
            done < <(lacy_collect_directory_entries "$ref_path")

            if (( listing_count == 0 )); then
                refs_block+="  - (empty directory)"$'\n'
            fi

            local excerpt_count=0
            local file
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if lacy_is_text_file "$file"; then
                    refs_block+="Text excerpts:"$'\n'
                    break
                fi
            done < <(find "$ref_path" -maxdepth "${LACY_REF_DIR_MAX_DEPTH:-3}" -type f | LC_ALL=C sort | head -n "${LACY_REF_DIR_MAX_FILES:-12}")

            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if ! lacy_is_text_file "$file"; then
                    continue
                fi
                refs_block+="  - ${file}"$'\n'
                refs_block+="\`\`\`text"$'\n'
                refs_block+="$(head -c "${LACY_REF_MAX_BYTES:-8192}" "$file" 2>/dev/null)"$'\n'
                refs_block+="\`\`\`"$'\n'
                excerpt_count=$(( excerpt_count + 1 ))
                if (( excerpt_count >= ${LACY_REF_DIR_MAX_FILES:-12} )); then
                    break
                fi
            done < <(find "$ref_path" -maxdepth "${LACY_REF_DIR_MAX_DEPTH:-3}" -type f | LC_ALL=C sort)
        fi
    done

    if [[ -z "$refs_block" ]]; then
        printf '%s' "$query"
        return
    fi

    printf '%s\n%s\n\n%s' \
        "[Lacy referenced paths]" \
        "${refs_block#$'\n'}" \
        "$query"
}
