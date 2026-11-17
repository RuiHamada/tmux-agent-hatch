# shellcheck shell=bash
# Shared by hatch-*: with a leading `--host <ssh-host>` (or HATCH_HOST), run the same command on
# that ssh host and exit. The host needs openclaw/install.sh --remote as well.
hatch_remote_cmd() {   # <host> <cmd> <args...>: run over ssh (without exec)
  local host="$1" cmd="$2"; shift 2
  local q="" a
  for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  # -n: never read the caller's stdin (inside a `while read` loop ssh would swallow the remaining lines)
  ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$host" "PATH=\$HOME/.local/bin:\$PATH $cmd$q"
}
hatch_remote_dispatch() {
  local host="${HATCH_HOST:-}" cmd
  cmd="$(basename "$0")"
  if [ "${1:-}" = --host ]; then host="$2"; shift 2; fi
  [ -n "$host" ] || return 0
  hatch_remote_cmd "$host" "$cmd" "$@"; exit $?
}
# hatch_detach <cmd> <args...>: run in the background in a session of its own, so that a caller that kills
# its whole process group when the command returns (OpenClaw's exec does) does not take it down too.
hatch_detach() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys
if os.fork(): os._exit(0)
os.setsid()
if os.fork(): os._exit(0)
fd=os.open(os.devnull, os.O_RDWR)
for i in (0,1,2): os.dup2(fd,i)
os.execvp(sys.argv[1], sys.argv[1:])' "$@" >/dev/null 2>&1
  else
    ( "$@" >/dev/null 2>&1 & )
  fi
}
# With HATCH_NO_DISPATCH set, the caller parses --host itself; leave the arguments alone.
if [ -z "${HATCH_NO_DISPATCH:-}" ]; then
  hatch_remote_dispatch "$@"
  if [ "${1:-}" = --host ]; then shift 2; fi
fi
