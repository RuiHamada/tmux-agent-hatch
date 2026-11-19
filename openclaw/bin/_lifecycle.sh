# shellcheck shell=bash
# Serialize coordinator operations spanning a ledger decision and a tmux action.
# The parent owns the lock until the command returns. Never pass the descriptor
# to a tmux server or a detached reap. The kernel releases it on process exit.
# Lock the caller's open file description (passed as stdin). Never steal a slow writer's lock.
hatch_flock() {
  perl -MFcntl=:flock -MTime::HiRes=time,sleep -e '
    my $deadline = time + $ARGV[0];
    until (flock(STDIN, LOCK_EX | LOCK_NB)) {
      die "flock: $!" unless $!{EWOULDBLOCK};
      if (time >= $deadline) { print STDERR "refused: $ARGV[1] lock busy\n"; exit 3 }
      sleep 0.05;
    }' "${HATCH_LOCK_TIMEOUT:-15}" "$1"
}

# Serialize all metadata read/modify/write operations, including hook updates.
hatch_update_meta() (
  local meta="$1" tmp; shift
  exec 8>>"$meta.lock" || exit 1
  hatch_flock metadata <&8 || exit $?
  tmp="$(mktemp "$meta.XXXXXX")" || exit 1
  trap 'rm -f "$tmp"' EXIT
  jq "$@" "$meta" >"$tmp" && mv -f "$tmp" "$meta"
)
hatch_lock_command() {
  if [ -n "${HATCH_LIFECYCLE_LOCKED:-}" ]; then unset HATCH_LIFECYCLE_LOCKED; return; fi
  local ledger="${HATCH_LEDGER:-$HOME/.openclaw/hatch-ledger.tsv}"
  mkdir -p "$(dirname "$ledger")" || exit 1
  (
    hatch_flock lifecycle <&9 || exit $?
    HATCH_LIFECYCLE_LOCKED=1 "$@" 9>&-
    exit $?
  ) 9>>"$ledger.lifecycle"
  exit $?
}
