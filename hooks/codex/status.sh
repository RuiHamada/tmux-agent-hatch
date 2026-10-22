#!/usr/bin/env bash
# Codex lifecycle hook: keep a status file shaped like Claude Code's
# ~/.claude/sessions/*.json, so scripts/agents.sh can list Codex the same way.
#
# Reads the hook payload on stdin (session_id, cwd, hook_event_name, ...) and
# writes $CODEX_HOME/hatch-status/<pid>.json, where <pid> is the Codex process
# that owns this hook. Rings the bell on Stop / PermissionRequest and refreshes
# the picker cache on every event. Never fails and never prints.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set HATCH_DEBUG_LOG=/path to trace what each invocation saw and did.
log() { [ -n "${HATCH_DEBUG_LOG:-}" ] && printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$HATCH_DEBUG_LOG" 2>/dev/null; return 0; }

input="$(cat 2>/dev/null)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
log "event=$event ppid=$PPID tmux_pane=${TMUX_PANE:-} input=${input:0:120}"
[ -n "$event" ] || exit 0

dir="${CODEX_HOME:-$HOME/.codex}/hatch-status"

# The hook runs as a child (or grandchild, via sh -c) of the Codex process. Walk
# up the parent chain until the command name looks like codex.
pid="$PPID"
codex_pid=""
for _ in 1 2 3 4 5; do
  [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || break
  comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
  case "${comm##*/}" in
  codex*) codex_pid="$pid"; break ;;
  esac
  pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
done
log "codex_pid=${codex_pid:-none} chain-from=$PPID"
[ -n "$codex_pid" ] || exit 0

file="${dir:?}/${codex_pid:?}.json"

refresh() { "$DIR/../refresh-cache.sh" "${1:-0}" 2>/dev/null; }

# Prune files of Codex processes that are gone (crash, kill -9: no SessionEnd).
# agents.sh ignores them anyway; this just keeps the directory from growing.
for stale in "$dir"/*.json; do
  [ -f "$stale" ] || continue
  spid="${stale##*/}"; spid="${spid%.json}"
  case "$spid" in *[!0-9]*) continue ;; esac
  kill -0 "$spid" 2>/dev/null || rm -f "${stale:?}" 2>/dev/null
done

case "$event" in
SessionStart)      status=idle ;;
UserPromptSubmit)  status=busy ;;
PermissionRequest) status=waiting ;;
Stop)              status=idle ;;
SessionEnd)
  rm -f "${file:?}" 2>/dev/null
  log "removed $file"
  refresh 0.3
  exit 0
  ;;
*) exit 0 ;;
esac

# Start time in the exact shape agents.sh compares against (ps lstart, UTC,
# single-spaced), so a recycled pid is never mistaken for a live agent.
start="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$codex_pid" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')"
[ -n "$start" ] || exit 0

mkdir -p "$dir" 2>/dev/null || exit 0
tmp="${dir:?}/.${codex_pid:?}.$$"
if jq -n --argjson pid "$codex_pid" --arg status "$status" --arg sid "$sid" --arg cwd "$cwd" \
  --argjson now "$(( $(date +%s) * 1000 ))" --arg start "$start" \
  '{kind: "interactive", agent: "codex", pid: $pid, status: $status, sessionId: $sid, cwd: $cwd,
    statusUpdatedAt: $now, procStart: $start}' >"$tmp" 2>/dev/null; then
  mv -f "$tmp" "$file" 2>/dev/null && log "wrote $file status=$status"
else
  log "jq failed for $file"
  rm -f "${tmp:?}" 2>/dev/null
fi

case "$event" in
Stop | PermissionRequest) "$DIR/../bell.sh" 2>/dev/null ;;
esac
refresh
exit 0
