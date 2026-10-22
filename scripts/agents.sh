#!/usr/bin/env bash
# Emit one picker row per running agent (Claude Code or Codex) that lives in a
# tmux pane. (modified from tmux-claude-hatch: adds Codex records and an agent column)
#
# Claude self-reports its status: each session writes its own state to disk
# (~/.claude/sessions/*.json), falling back to `claude agents --json`. Codex has
# no such file, so hooks/codex/status.sh writes an equivalent one under
# $CODEX_HOME/hatch-status/ from Codex's lifecycle hooks.
#
# Identity is the agent process, not the tmux session. Joining pid -> tty -> pane
# is what lets several agents in one project each get a row of their own.
#
#   Row: rank \t pane_id \t pid \t kind \t agent \t icon \t age \t loc \t path
#   rank/pane_id/pid/kind are hidden from the display via fzf's --with-nth.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

#   Rec: pid \t status \t session-id \t cwd \t seen-at \t proc-start \t agent \t verify
# `verify` is 1 when the record came from a status file and liveness is on us:
# a crashed agent leaves its file behind and the pid may since have been recycled,
# so such a rec counts only while that pid still has the start time the file
# recorded. CLI records have already dropped dead agents, so verify is empty.

claude_file_recs() {
  local files
  files=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/sessions/*.json)
  [ -f "${files[0]}" ] || return 1
  jq -r 'select(.kind == "interactive")
    | ((.statusUpdatedAt // .updatedAt) as $t | if $t then ($t / 1000 | floor) else "" end) as $seen
    | [.pid, .status, .sessionId, .cwd, $seen, .procStart, "claude", "1"] | @tsv' "${files[@]}" 2>/dev/null
}

# Fallback when the session files can't be read. It reports no last-activity time;
# the transcript's mtime stands in for it.
claude_cli_recs() {
  $(get_tmux_option @claude_command 'claude') agents --json 2>/dev/null |
    jq -r '.[] | select(.kind == "interactive") | [.pid, .status, .sessionId, .cwd] | @tsv' 2>/dev/null |
    while IFS=$'\t' read -r pid status sid cwd; do
      printf '%s\t%s\t%s\t%s\t%s\t\tclaude\t\n' "$pid" "$status" "$sid" "$cwd" "$(claude_transcript_mtime "$sid")"
    done
}

codex_recs() {
  local files
  files=("${CODEX_HOME:-$HOME/.codex}"/hatch-status/*.json)
  [ -f "${files[0]}" ] || return 1
  jq -r '((.statusUpdatedAt // 0) / 1000 | floor | tostring) as $seen
    | [.pid, .status, .sessionId, .cwd, $seen, .procStart, "codex", "1"] | @tsv' "${files[@]}" 2>/dev/null
}

# well_formed <recs>: every verified rec carries pid, status, cwd and proc-start.
# A rec missing one means the file format moved on; the caller falls back.
well_formed() {
  [ -n "$1" ] || return 1
  printf '%s\n' "$1" |
    awk -F'\t' '$8 == "1" && ($1 == "" || $2 == "" || $4 == "" || $6 == "") { bad = 1 } END { exit bad }'
}

# proc_starts <recs>
# Linux only: Claude records field 22 of /proc/<pid>/stat as proc-start there.
# Strip greedily past ") " first — field 2 is the parenthesised command name and
# may itself contain ") " — which leaves field 22 as the 20th of what remains.
proc_starts() {
  printf '%s\n' "$1" | cut -f1 | while IFS= read -r pid; do
    IFS= read -r stat 2>/dev/null <"/proc/$pid/stat" || continue
    # shellcheck disable=SC2086 # deliberate split into positional parameters
    set -- ${stat##*) }
    [ $# -ge 20 ] && printf 'S\t%s\t%s\n' "$pid" "${20}"
  done
}

# render <recs>
# Tagged streams into one awk: pid->tty+start, tty->pane, and the agents. One `ps`
# serves both joins, which matters on macOS where each call costs over 100ms.
render() {
  {
    # Rejoining the fields with single spaces undoes the padding of a
    # single-digit day ("Sep  1").
    TZ=UTC LC_ALL=C ps -o pid=,tty=,lstart= -p "$(printf '%s\n' "$1" | cut -f1 | paste -sd, -)" 2>/dev/null |
      awk '{ print "P\t" $1 "\t" $2 "\t" $3 " " $4 " " $5 " " $6 " " $7 }'
    [ -r /proc/self/stat ] && proc_starts "$1"
    # tmux 3.4 (Linux distros) replaces a tab inside -F output with "_", so the
    # fields come space-separated with the free-text session name last, and are
    # re-joined with tabs here. (modified from tmux-claude-hatch)
    tmux list-panes -a -F '#{pane_tty} #{pane_id} #{window_index}.#{pane_index} #{session_name}' 2>/dev/null |
      while read -r tty_ pane_ wp_ sess_; do
        printf 'T\t%s\t%s\t%s\t%s:%s\n' "$tty_" "$pane_" "$sess_" "$sess_" "$wp_"
      done
    printf '%s\n' "$1" | sed $'s/^/A\t/'
  } | awk -F'\t' -v now="$(date +%s)" -v home="$HOME" -v prefixes="$(hatch_prefixes)" '
    BEGIN { np = split(prefixes, pfx, " ") }
    $1 == "P" { tty_of[$2] = $3; start[$2] = $4; next }
    $1 == "S" { start[$2] = $3; next }
    $1 == "T" { sub(/^\/dev\//, "", $2); pane[$2] = $3; sess[$2] = $4; loc[$2] = $5; next }
    $1 == "A" && $2 != "" {
      if ($9 == "1") {
        gsub(/ +/, " ", $7)
        if (start[$2] != $7) next             # stale file: dead, or the pid was recycled
      }

      tty = tty_of[$2]
      if (tty == "" || !(tty in pane)) next   # this agent is not running inside tmux

      if      ($3 == "waiting") { icon = "\033[33m●\033[0m waiting"; rank = 0 }  # yellow - needs input
      else if ($3 == "idle")    { icon = "\033[32m●\033[0m idle   "; rank = 1 }  # green  - done, your turn
      else if ($3 == "busy")    { icon = "\033[31m●\033[0m working"; rank = 3 }  # red    - busy, leave it
      else                      { icon = "\033[90m●\033[0m   ?    "; rank = 2 }  # grey   - unrecognised status

      secs = ($6 != "") ? now - $6 : 1e12   # unknown activity sorts last
      mins = int(secs / 60)
      if      ($6 == "")    age = "-"
      else if (mins < 60)   age = mins "m"
      else if (mins < 2880) age = int(mins / 60) "h"
      else                  age = int(mins / 1440) "d"

      kind = "loose"
      for (i = 1; i <= np; i++) if (index(sess[tty], pfx[i]) == 1) { kind = "dedicated"; break }

      path = $5
      if (index(path, home) == 1) path = "~" substr(path, length(home) + 1)

      printf "%d\t%s\t%s\t%s\t%s\t%-6s\t%s\t%5s\t%s\t%s\n",
        secs, rank, pane[tty], $2, kind, $8, icon, age, loc[tty], path
    }
  ' | sort -t$'\t' $sort_keys | cut -f2-
  # The age column mixes units ("5m", "3h", "2d"), so the sort runs on a leading
  # seconds column, cut off once it has served.
}

# status: rank asc (what needs you floats up), then age asc so whatever just went
# idle sits at the top of its group. recent: age asc alone.
if [ "$(get_tmux_option @claude_sort 'status')" = recent ]; then
  sort_keys='-k1,1n'
else
  sort_keys='-k2,2n -k1,1n'
fi

claude="$(claude_file_recs)"
well_formed "$claude" || claude="$(claude_cli_recs)"
codex="$(codex_recs)"
well_formed "$codex" || codex=''

recs="$(printf '%s\n%s\n' "$claude" "$codex" | sed '/^$/d')"
[ -n "$recs" ] || exit 0
out="$(render "$recs")"
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
