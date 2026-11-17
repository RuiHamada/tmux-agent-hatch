# shellcheck shell=bash
# Shared by hatch-*: with a leading `--host <ssh-host>` (or HATCH_HOST), run the same command on
# that ssh host and exit. The host needs openclaw/install.sh --remote as well.
hatch_remote_cmd() {   # <host> <cmd> <args...>: run over ssh (without exec)
  local host="$1" cmd="$2"; shift 2
  local q="" a
  for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" "PATH=\$HOME/.local/bin:\$PATH $cmd$q"
}
hatch_remote_dispatch() {
  local host="${HATCH_HOST:-}" cmd
  cmd="$(basename "$0")"
  if [ "${1:-}" = --host ]; then host="$2"; shift 2; fi
  [ -n "$host" ] || return 0
  hatch_remote_cmd "$host" "$cmd" "$@"; exit $?
}
# With HATCH_NO_DISPATCH set, the caller parses --host itself; leave the arguments alone.
if [ -z "${HATCH_NO_DISPATCH:-}" ]; then
  hatch_remote_dispatch "$@"
  if [ "${1:-}" = --host ]; then shift 2; fi
fi
