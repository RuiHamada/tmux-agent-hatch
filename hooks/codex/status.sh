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

# Which Codex process owns this session? Two cases:
#
# 1. The hook runs as a child (or grandchild, via sh -c) of the Codex TUI: walk
#    up the parent chain until the command name looks like codex.
# 2. The TUI hands the session to the app-server daemon, and the hook runs under
#    the daemon, which has no tty and lives in no tmux pane. Then find the TUI by
#    matching the payload's cwd against the tmux panes that host a codex process.
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
found_by=chain

# is_codex <pid>: command name looks like codex.
is_codex() {
  local c
  c="$(ps -o comm= -p "$1" 2>/dev/null)"
  case "${c##*/}" in codex*) return 0 ;; esac
  return 1
}

# pane_codex_pids: one "pid<TAB>cwd" per codex process that is a tmux pane's own
# process or a direct child of it (a dedicated session runs codex as the pane
# command; a loose one runs it under the pane's shell).
pane_codex_pids() {
  # Space-separated (tmux 3.4 mangles tabs in -F output); the path, which may
  # contain spaces, is last so `read` keeps it whole.
  tmux list-panes -a -F '#{pane_pid} #{pane_current_path}' 2>/dev/null |
    while read -r ppid_ path_; do
      if is_codex "$ppid_"; then
        printf '%s\t%s\n' "$ppid_" "$path_"
        continue
      fi
      for c in $(pgrep -P "$ppid_" 2>/dev/null); do
        is_codex "$c" && printf '%s\t%s\n' "$c" "$path_"
      done
    done
}

# No controlling tty: "??" on macOS, "?" on Linux.
case "$(ps -o tty= -p "${codex_pid:-0}" 2>/dev/null | tr -d ' ')" in
'?' | '??') no_tty=1 ;;
*) no_tty='' ;;
esac
if [ -n "$codex_pid" ] && [ -n "$no_tty" ]; then
  # Case 2. Prefer a pane whose cwd matches; among several, the one not yet
  # claimed by a different live session; finally the newest.
  codex_pid=""
  found_by=pane
  best=""
  # Compare physical paths: tmux reports /private/tmp/x where the payload may say /tmp/x.
  canon() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
  want="$(canon "$cwd")"
  while IFS=$'\t' read -r cpid cpath; do
    [ -n "$cpid" ] || continue
    [ "$(canon "$cpath")" = "$want" ] || continue
    owner="$(jq -r '.sessionId // empty' "$dir/$cpid.json" 2>/dev/null)"
    if [ -z "$owner" ] || [ "$owner" = "$sid" ]; then
      codex_pid="$cpid"
      break
    fi
    best="$cpid"
  done <<EOF_PANES
$(pane_codex_pids)
EOF_PANES
  [ -n "$codex_pid" ] || codex_pid="$best"
fi
log "codex_pid=${codex_pid:-none} by=$found_by chain-from=$PPID"
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

# Start time in the exact shape agents.sh compares against, so a recycled pid
# is never mistaken for a live agent. Linux: field 22 of /proc/<pid>/stat (what
# Claude Code records there too). Elsewhere: ps lstart in UTC, single-spaced.
start=""
if [ -r "/proc/$codex_pid/stat" ]; then
  IFS= read -r stat_ <"/proc/$codex_pid/stat" 2>/dev/null
  # shellcheck disable=SC2086 # deliberate split past the ") " that ends the comm field
  set -- ${stat_##*) }
  [ $# -ge 20 ] && start="${20}"
else
  start="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$codex_pid" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')"
fi
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
