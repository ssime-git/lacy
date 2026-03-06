#!/usr/bin/env bash

# Normalized agent events + provider adapters.
# Shared across Bash 4+ and ZSH.

LACY_EVENT_PREFIX=$'LACY_EVENT\t'

lacy_emit_event() {
    local type="$1"
    shift
    local part
    printf '%s%s' "$LACY_EVENT_PREFIX" "$type"
    for part in "$@"; do
        part="${part//$'\t'/ }"
        part="${part//$'\r'/}"
        printf '\t%s' "$part"
    done
    printf '\n'
}

lacy_is_event_line() {
    [[ "$1" == "${LACY_EVENT_PREFIX}"* ]]
}

_lacy_provider_skip_line() {
    local tool="$1"
    local line="$2"

    case "$tool" in
        codex)
            case "$line" in
                "OpenAI Codex v"*|"--------"|"workdir: "*|"model: "*|"provider: "*|"approval: "*|"sandbox: "*|"reasoning effort: "*|"reasoning summaries: "*|"session id: "*|"user"|"mcp startup: "*|"Reconnecting... "*"tokens used") return 0 ;;
            esac
            ;;
    esac

    return 1
}

_lacy_parse_json_event_blob() {
    local tool="$1"
    local payload="$2"

    command -v python3 >/dev/null 2>&1 || return 1

    LACY_EVENT_TOOL="$tool" LACY_EVENT_PAYLOAD="$payload" python3 - <<'PY'
import json
import os
import sys

tool = os.environ.get("LACY_EVENT_TOOL", "")
payload = os.environ.get("LACY_EVENT_PAYLOAD", "")
prefix = "LACY_EVENT\t"

def emit(kind, *parts):
    clean = []
    for part in parts:
        if part is None:
            clean.append("")
        else:
            clean.append(str(part).replace("\t", " ").replace("\r", ""))
    sys.stdout.write(prefix + kind)
    if clean:
        sys.stdout.write("\t" + "\t".join(clean))
    sys.stdout.write("\n")

def pick(obj, *names):
    for name in names:
        if isinstance(obj, dict) and name in obj and obj[name] not in (None, ""):
            return obj[name]
    return None

def walk(value):
    if isinstance(value, list):
        for item in value:
            walk(item)
        return

    if not isinstance(value, dict):
        if isinstance(value, str) and value:
            emit("final_text", value)
        return

    event_type = str(pick(value, "type", "event", "kind", "status") or "").lower()
    part = value.get("part")
    part_type = str(pick(part or {}, "type", "event", "kind", "status") or "").lower()

    if tool == "opencode" and isinstance(part, dict):
        if event_type in {"reasoning", "thinking"} or part_type in {"reasoning", "thinking"}:
            emit("thinking_start")
            emit("thinking_delta", pick(part, "text", "content", "message", "summary") or "")
            emit("thinking_end")
            return
        if event_type in {"text", "final_text", "final-text"} or part_type in {"text", "final_text", "final-text"}:
            emit("final_text", pick(part, "text", "content", "message", "summary") or "")
            return
        if event_type in {"tool_use", "tool-use"}:
            state = part.get("state") if isinstance(part.get("state"), dict) else {}
            detail = pick(state, "title")
            if not detail:
                detail = json.dumps(pick(state, "input") or "", ensure_ascii=True)
            summary = pick(state, "output", "title")
            if summary is None:
                summary = ""
            elif not isinstance(summary, str):
                summary = json.dumps(summary, ensure_ascii=True)
            emit("action_start", pick(part, "tool", "name", "title") or "", detail or "")
            emit("action_result", pick(part, "tool", "name", "title") or "", pick(state, "status") or "", summary)
            return
        if event_type in {"step_finish", "step-finish"} or part_type in {"step_finish", "step-finish"}:
            reason = str(pick(part, "reason", "status", "state") or "").lower()
            if reason in {"stop", "end_turn", "end-turn"}:
                emit("done")
            elif reason:
                emit("status", f"step finish: {reason}")
            return

    if event_type in {"thinking_start", "thinking-start", "reasoning_start", "reasoning-start"}:
        emit("thinking_start")
        return
    if event_type in {"thinking_end", "thinking-end", "reasoning_end", "reasoning-end"}:
        emit("thinking_end")
        return
    if event_type in {"thinking", "thinking_delta", "thinking-delta", "reasoning", "reasoning_delta", "reasoning-delta"}:
        emit("thinking_delta", pick(value, "text", "content", "delta", "message", "summary") or "")
        return
    if event_type in {"status", "step", "progress"}:
        emit("status", pick(value, "message", "text", "content", "summary") or "")
        return
    if event_type in {"todo", "todo_item", "todo-item"}:
        state = pick(value, "state", "status", "checked", "done")
        if isinstance(state, bool):
            state = "checked" if state else "unchecked"
        elif str(state).lower() in {"true", "done", "completed", "checked", "complete"}:
            state = "checked"
        else:
            state = "unchecked"
        emit("todo_item", state, pick(value, "text", "content", "message", "title") or "")
        return
    if event_type in {"action_start", "action-start", "tool_call", "tool-call", "tool_start", "tool-start", "step_start", "step-start"}:
        emit("action_start", pick(value, "name", "tool", "title") or "", pick(value, "detail", "message", "summary", "input") or "")
        return
    if event_type in {"action_result", "action-result", "tool_result", "tool-result", "tool_end", "tool-end", "step_result", "step-result"}:
        emit("action_result", pick(value, "name", "tool", "title") or "", pick(value, "status", "state", "result") or "", pick(value, "summary", "message", "detail", "output") or "")
        return
    if event_type in {"final", "final_text", "final-text", "assistant_message", "assistant-message", "message", "output", "response"}:
        emit("final_text", pick(value, "text", "content", "message", "result", "summary") or "")
        return
    if event_type in {"error", "tool_error", "tool-error"} or value.get("is_error") is True:
        emit("error", pick(value, "message", "result", "error", "summary") or "Agent error")
        return

    parts = value.get("parts")
    if isinstance(parts, list):
        texts = []
        for part in parts:
            if isinstance(part, dict):
                part_type = str(part.get("type", "")).lower()
                if part_type in {"text", "output_text"} and part.get("text"):
                    texts.append(part["text"])
                elif part_type in {"thinking", "reasoning"} and part.get("text"):
                    emit("thinking_start")
                    emit("thinking_delta", part["text"])
                    emit("thinking_end")
                elif part_type in {"step-finish", "step_finish"}:
                    reason = str(part.get("reason", "")).lower()
                    if reason in {"stop", "end_turn", "end-turn"}:
                        emit("done")
        if texts:
            emit("final_text", "\n".join(texts))
            return

    for key in ("result", "content", "text", "message", "response"):
        val = value.get(key)
        if isinstance(val, str) and val:
            emit("final_text", val)
            return

    if tool == "opencode":
        # Best-effort recovery for unfamiliar payloads.
        emit("final_text", json.dumps(value, ensure_ascii=True))

data = payload.strip()
if not data:
    raise SystemExit(1)

parsed = None
try:
    parsed = json.loads(data)
except Exception:
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            walk(json.loads(line))
        except Exception:
            raise SystemExit(1)
    raise SystemExit(0)

walk(parsed)
PY
}

lacy_agent_normalize_blob() {
    local tool="$1"
    local payload="$2"

    if lacy_is_event_line "$payload"; then
        printf '%s\n' "$payload"
        return 0
    fi

    if [[ "$payload" == "{"* || "$payload" == "["* ]]; then
        if _lacy_parse_json_event_blob "$tool" "$payload" 2>/dev/null; then
            return 0
        fi
    fi

    printf '%s\n' "$payload"
}

lacy_agent_normalize_line() {
    local tool="$1"
    local line="$2"

    _lacy_provider_skip_line "$tool" "$line" && return 0

    if lacy_is_event_line "$line"; then
        printf '%s\n' "$line"
        return 0
    fi

    if [[ "$line" == "{"* || "$line" == "["* ]]; then
        if _lacy_parse_json_event_blob "$tool" "$line" 2>/dev/null; then
            return 0
        fi
    fi

    case "$tool" in
        opencode)
            case "$line" in
                "> "*)
                    lacy_emit_event "status" "${line#> }"
                    return 0
                    ;;
                "✱ "*)
                    lacy_emit_event "action_start" "${line#✱ }" ""
                    return 0
                    ;;
                "→ "*)
                    lacy_emit_event "action_result" "${line#→ }" "ok" ""
                    return 0
                    ;;
            esac
            ;;
    esac

    printf '%s\n' "$line"
}

lacy_agent_normalize_stream() {
    local tool="$1"
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        lacy_agent_normalize_line "$tool" "$line"
    done
}
