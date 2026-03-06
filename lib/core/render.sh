#!/usr/bin/env bash

# Output rendering for Lacy Shell.
# Shared across Bash 4+ and ZSH.

_LACY_IN_CODE_BLOCK=0
_LACY_IN_THINKING_BLOCK=0
_LACY_THINKING_VISIBLE=0
_LACY_TODO_PRINTED=0
_LACY_TODO_COUNT=0
_LACY_TODO_TEXTS=()
_LACY_TODO_STATES=()

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
    _LACY_TODO_PRINTED=0
    _LACY_TODO_COUNT=0
    _LACY_TODO_TEXTS=()
    _LACY_TODO_STATES=()
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

_lacy_finish_todo_block() {
    _LACY_TODO_PRINTED=0
}

_lacy_todo_set_item() {
    local state="$1"
    local text="$2"
    local i

    for (( i = 1; i <= _LACY_TODO_COUNT; i++ )); do
        if [[ "${_LACY_TODO_TEXTS[$i]}" == "$text" ]]; then
            _LACY_TODO_STATES[$i]="$state"
            return
        fi
    done

    _LACY_TODO_COUNT=$(( _LACY_TODO_COUNT + 1 ))
    _LACY_TODO_TEXTS[$_LACY_TODO_COUNT]="$text"
    _LACY_TODO_STATES[$_LACY_TODO_COUNT]="$state"
}

_lacy_render_todo_block() {
    local i

    if (( _LACY_TODO_PRINTED > 0 )); then
        for (( i = 0; i < _LACY_TODO_PRINTED; i++ )); do
            printf '\e[1A\e[2K\r'
        done
    fi

    for (( i = 1; i <= _LACY_TODO_COUNT; i++ )); do
        if [[ "${_LACY_TODO_STATES[$i]}" == "checked" ]]; then
            lacy_print_color 34 "☑ ${_LACY_TODO_TEXTS[$i]}"
        else
            lacy_print_color 238 "☐ ${_LACY_TODO_TEXTS[$i]}"
        fi
    done

    _LACY_TODO_PRINTED=$_LACY_TODO_COUNT
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

_lacy_render_event_line() {
    local event_line="$1"
    local rest="${event_line#${LACY_EVENT_PREFIX}}"
    local type="${rest%%$'\t'*}"
    local args=""
    [[ "$rest" == *$'\t'* ]] && args="${rest#*$'\t'}"

    local arg1="" arg2="" arg3=""
    if [[ -n "$args" ]]; then
        IFS=$'\t' read -r arg1 arg2 arg3 <<< "$args"
    fi

    case "$type" in
        thinking_start|thinking_delta|thinking_end|todo_item) ;;
        *)
            if (( _LACY_IN_THINKING_BLOCK == 1 )); then
                _lacy_finish_thinking_block
            fi
            _lacy_finish_todo_block
            ;;
    esac

    case "$type" in
        status)
            lacy_show_agent_step "$arg1"
            ;;
        thinking_start)
            _lacy_start_thinking_block
            ;;
        thinking_delta)
            _lacy_render_thinking_line "$arg1"
            ;;
        thinking_end)
            _lacy_finish_thinking_block
            ;;
        todo_item)
            _lacy_todo_set_item "$arg1" "$arg2"
            _lacy_render_todo_block
            ;;
        action_start)
            if [[ -n "$arg2" ]]; then
                lacy_show_agent_step "${arg1}: ${arg2}"
            else
                lacy_show_agent_step "$arg1"
            fi
            ;;
        action_result)
            if [[ -n "$arg3" ]]; then
                lacy_show_agent_step "${arg1} [${arg2}]: ${arg3}"
            elif [[ -n "$arg2" ]]; then
                lacy_show_agent_step "${arg1} [${arg2}]"
            else
                lacy_show_agent_step "$arg1"
            fi
            ;;
        text_delta|final_text)
            _lacy_render_stream_line "$arg1"
            ;;
        error)
            lacy_print_color 196 "$arg1"
            ;;
        done)
            ;;
        *)
            _lacy_render_stream_line "$event_line"
            ;;
    esac
}

lacy_render_response() {
    _lacy_reset_render_state

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if lacy_is_event_line "$line"; then
            _lacy_render_event_line "$line"
        else
            _lacy_render_stream_line "$line"
        fi
    done

    if (( _LACY_IN_THINKING_BLOCK == 1 )); then
        _lacy_finish_thinking_block
    fi
}
