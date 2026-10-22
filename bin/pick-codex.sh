#!/usr/bin/env bash
# fzf でセッションを選び、名前を標準出力に出す(list-codex.sh が受け取る)。
# ctrl-x で選択中のセッションを kill。
set -uo pipefail
prefix="${1:-codex-}"
home="$HOME"

list() {
  tmux list-sessions -F $'#{session_name}\t#{session_activity}\t#{session_path}' 2>/dev/null |
    awk -F'\t' -v p="$prefix" -v now="$(date +%s)" -v home="$home" '
      index($1, p) == 1 {
        secs = now - $2; mins = int(secs / 60)
        age = (mins < 60) ? mins "m" : (mins < 2880) ? int(mins / 60) "h" : int(mins / 1440) "d"
        path = $3; if (index(path, home) == 1) path = "~" substr(path, length(home) + 1)
        printf "%s\t%5s\t%s\n", $1, age, path
      }' | sort -t$'\t' -k2,2
}

export -f list
export prefix home
list | fzf --ansi --delimiter=$'\t' --with-nth=1,2,3 --no-sort \
  --header 'enter: open  ctrl-x: kill  esc: close' \
  --preview 'tmux capture-pane -ep -t {1}' --preview-window 'right:60%' \
  --bind 'ctrl-x:execute-silent(tmux kill-session -t {1})+reload(bash -c list)' |
  cut -f1
