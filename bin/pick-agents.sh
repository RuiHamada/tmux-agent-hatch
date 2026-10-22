#!/usr/bin/env bash
# 全エージェントセッション(claude-* / codex-* など)を fzf で選び、名前を標準出力に出す。
# list-agents.sh が受け取る。ctrl-x で選択中のセッションを kill。
# Args: <prefixes>  空白区切り(例: "claude- codex-")
set -uo pipefail
prefixes="${1:-claude- codex-}"
home="$HOME"

list() {
  tmux list-sessions -F $'#{session_name}\t#{session_activity}\t#{session_path}\t#{session_attached}' 2>/dev/null |
    awk -F'\t' -v ps="$prefixes" -v now="$(date +%s)" -v home="$home" '
      BEGIN { n = split(ps, p, " ") }
      {
        kind = ""
        for (i = 1; i <= n; i++) if (index($1, p[i]) == 1) { kind = substr(p[i], 1, length(p[i]) - 1); break }
        if (kind == "") next
        secs = now - $2; mins = int(secs / 60)
        age = (mins < 60) ? mins "m" : (mins < 2880) ? int(mins / 60) "h" : int(mins / 1440) "d"
        path = $3; if (index(path, home) == 1) path = "~" substr(path, length(home) + 1)
        open = ($4 > 0) ? "open" : "    "
        printf "%d\t%s\t%-6s\t%s\t%5s\t%s\n", secs, $1, kind, open, age, path
      }' | sort -t$'\t' -k1,1n | cut -f2-
}

export -f list
export prefixes home
list | fzf --ansi --delimiter=$'\t' --with-nth=2,3,4,5 --no-sort \
  --header 'enter: open  ctrl-x: kill  esc: close' \
  --preview 'tmux capture-pane -ep -t {1}' --preview-window 'right:60%' \
  --bind 'ctrl-x:execute-silent(tmux kill-session -t {1})+reload(bash -c list)' |
  cut -f1
