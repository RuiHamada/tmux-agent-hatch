# shellcheck shell=bash
# hatch_alive_pairs <ledger>: print "<host>/<session>" for every ledger session that still exists in tmux,
# with one tmux call for local rows and one ssh per remote host.
hatch_alive_pairs() {
  local ledger="$1" h
  for h in $(awk -F'\t' 'NR > 1 { print $2 }' "$ledger" | sort -u); do
    if [ "$h" = local ]; then
      tmux list-sessions -F '#S' 2>/dev/null | sed 's|^|local/|'
    else
      ssh -n -o BatchMode=yes -o ConnectTimeout=6 "$h" 'PATH=$HOME/.local/bin:$PATH tmux list-sessions -F "#S"' 2>/dev/null | sed "s|^|$h/|"
    fi
  done
}

# A successful listing may still omit a role or contain an unknown pane.
hatch_role_is_idle() {
  awk -F'\t' -v s="$1" '$6 == s { seen=1; if ($2 != "idle") uncertain=1 }
    END { exit !(seen && !uncertain) }'
}
