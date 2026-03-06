#!/usr/bin/env bash

# Output rendering for Lacy Shell.
# Shared across Bash 4+ and ZSH.

_LACY_IN_CODE_BLOCK=0
_LACY_IN_THINKING_BLOCK=0
_LACY_THINKING_VISIBLE=0

lacy_show_agent_step() {
    local message="$1"
    [[ "${LACY_SHOW_AGENT_STEPS:-true}" == "true" ]] || return
    [[ -n "$message" ]] || return
    lacy_print_color 75 "  > ${message}"
}

_lacy_reset_render_state() {
    _LACY_IN_CODE_BLOCK=0
    _LACY_IN_THINKING_BLOCK=0
    _LACY_THINKING_VISIBLE=0
}

_lacy_start_thinking_block() {
    if (( _LACY_THINKING_VISIBLE == 0 )); then
        lacy_print_color 238 "╭─ Thinking"
        _LACY_THINKING_VISIBLE=1
    fi
    _LACY_IN_THINKING_BLOCK=1
}

_lacy_finish_thinking_block() {
    if (( _LACY_IN_THINKING_BLOCK == 1 && _LACY_THINKING_VISIBLE == 1 )); then
        lacy_print_color 238 "╰─"
        echo ""
    fi
    _LACY_IN_THINKING_BLOCK=0
    _LACY_THINKING_VISIBLE=0
}

_lacy_render_thinking_line() {
    local line="$1"

    if [[ -z "$line" && _LACY_THINKING_VISIBLE -eq 0 ]]; then
        return
    fi

    _lacy_start_thinking_block
    lacy_print_color 238 "│ ${line}"
}

_lacy_render_plain_line() {
    local line="$1"

    if [[ "$line" == '```'* ]]; then
        if (( _LACY_IN_CODE_BLOCK == 0 )); then
            _LACY_IN_CODE_BLOCK=1
        else
            _LACY_IN_CODE_BLOCK=0
        fi
        lacy_print_color 238 "$line"
        return
    fi

    if (( _LACY_IN_CODE_BLOCK == 1 )); then
        case "$line" in
            "@@"*"@@"*) lacy_print_color 75 "$line" ;;
            "--- "*) lacy_print_color 238 "$line" ;;
            "+++ "*) lacy_print_color 238 "$line" ;;
            "+"*) lacy_print_color 34 "$line" ;;
            "-"*) lacy_print_color 196 "$line" ;;
            *) printf '%s\n' "$line" ;;
        esac
        return
    fi

    local stripped="${line#"${line%%[^ $'\t']*}"}"
    local indent="${line:0:$(( ${#line} - ${#stripped} ))}"

    if [[ "$stripped" == "- [ ] "* ]]; then
        lacy_print_color 238 "${indent}☐ ${stripped#"- [ ] "}"
    elif [[ "$stripped" == "- [x] "* ]]; then
        lacy_print_color 34 "${indent}☑ ${stripped#"- [x] "}"
    elif [[ "$stripped" == "- [X] "* ]]; then
        lacy_print_color 34 "${indent}☑ ${stripped#"- [X] "}"
    else
        printf '%s\n' "$line"
    fi
}

_lacy_render_stream_line() {
    local remaining="$1"

    while :; do
        if (( _LACY_IN_THINKING_BLOCK == 1 )); then
            if [[ "$remaining" == *"</thinking>"* ]]; then
                local thought="${remaining%%</thinking>*}"
                _lacy_render_thinking_line "$thought"
                remaining="${remaining#*</thinking>}"
                _lacy_finish_thinking_block
                [[ -n "$remaining" ]] || return
                continue
            fi
            _lacy_render_thinking_line "$remaining"
            return
        fi

        if [[ "$remaining" == *"<thinking>"* ]]; then
            local before="${remaining%%<thinking>*}"
            local after="${remaining#*<thinking>}"
            [[ -n "$before" ]] && _lacy_render_plain_line "$before"
            _lacy_start_thinking_block
            remaining="$after"
            continue
        fi

        _lacy_render_plain_line "$remaining"
        return
    done
}

lacy_render_response() {
    _lacy_reset_render_state

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        _lacy_render_stream_line "$line"
    done

    if (( _LACY_IN_THINKING_BLOCK == 1 )); then
        _lacy_finish_thinking_block
    fi
}
