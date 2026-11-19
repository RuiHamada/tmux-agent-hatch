# Regression cases from the P1 reviews. Use only run.sh's ledger and sockets.
echo "== P1 review: identifiers, ownership and locks"
review_repo="$W/review-repo"; git init -q "$review_repo"
role_run() { "$BIN/hatch-launch" --role research --repo "$1" --task "$2" "${@:3}"; }
led() { "$BIN/hatch-ledger" "$@"; }
led add local codex slow-session slow "$W/out/slow" slow
# Pause one real ledger rewrite past the former directory-lock takeover timer.
mkdir -p "$W/slow-bin"
cat >"$W/slow-bin/awk" <<'SLOW'
#!/bin/sh
if [ -n "${SLOW_LEDGER:-}" ]; then
  case "$*" in *'line[NR]'*)
    "$REAL_AWK" "$@" || exit $?
    touch "$SLOW_LEDGER"; sleep 7; exit 0 ;;
  esac
fi
exec "$REAL_AWK" "$@"
SLOW
chmod +x "$W/slow-bin/awk"
REAL_AWK="$(command -v awk)" SLOW_LEDGER="$W/slow-started" PATH="$W/slow-bin:$PATH" led note slow-session slow-update >/dev/null & slow=$!
waitfor '[ -f "$W/slow-started" ]'
led note slow-session newer-update >/dev/null; wait "$slow"
note="$(led show slow-session)"
check "slow ledger writer retains ownership until both notes persist" 'grep -q slow-update <<<"$note" && grep -q newer-update <<<"$note"'

msg="$("$BIN/hatch-launch" 2>&1)"; rc=$?
check "no arguments prints launch usage" '[ "$rc" = 2 ] && grep -q "usage:" <<<"$msg"'

r="$(role_run check-wt a codex "$review_repo" first)"; wsession="$(field "$r" session)"
role_run check-wt b --branch isolated codex "$review_repo" other >/dev/null 2>&1; rc=$?
check "explicit conflicting worktree is refused before delivery" '[ "$rc" = 3 ] && [ "$(tmux show-options -t "$wsession" -qv @hatch_task)" = a ]'

r="$(role_run check-meta a codex "$review_repo" first)"; mout="$(field "$r" out)"; msess="$(field "$r" session)"
led close "$msess" >/dev/null; mv "$mout/meta.json" "$W/saved-meta"
role_run check-meta b --fresh codex "$REPO" fresh >/dev/null 2>&1; rc=$?
check "fresh requires verifiable prior checkout" '[ "$rc" = 3 ] && [ "$(tmux show-options -t "$msess" -qv @hatch_out)" = "$mout" ]'

for state in open closed; do
  key="check-name-$state"; r="$(role_run "$key" "name-$state" codex "$review_repo" first)"
  name="$(field "$r" session)"; slug="$(field "$r" slug)"
  [ "$state" = open ] || led close "$name" >/dev/null
  tmux kill-session -t "=$name"
  r="$("$BIN/hatch-launch" --readonly --slug "$slug" codex "$review_repo" legacy)"
  check "legacy allocation reserves $state role names" '[ "$(field "$r" session)" = "$name-2" ] && [ "$(led status "$name" local)" = "$state" ]'
done

legacy_r="$("$BIN/hatch-launch" --readonly --slug shared-key claude "$review_repo" legacy)"
legacy_s="$(field "$legacy_r" session)"
rr="$(role_run check-key shared-key codex "$review_repo" independent)"; role_s="$(field "$rr" session)"
led close shared-key >/dev/null 2>&1; rc=$?
check "ambiguous close leaves both namespaces open" '[ "$rc" = 3 ] && [ "$(led status "$legacy_s" local)" = open ] && [ "$(led status "$role_s" local)" = open ]'
# Check both sides of the selection before performing the separate legacy close.
both_open=""
[ "$(led status "$role_s" local)" = open ] && [ "$(led status "$legacy_s" local)" = open ] && both_open=1
led close --task shared-key >/dev/null 2>&1; selector_rc=$?
check "explicit task close affects only the role row" '[ -n "$both_open" ] && [ "$selector_rc" = 0 ] && [ "$(led status "$role_s" local)" = closed ] && [ "$(led status "$legacy_s" local)" = open ] && alive "$legacy_s"'
led close "$legacy_s" >/dev/null
check "explicit task close and synchronous legacy close" '[ "$(led status "$role_s" local)" = closed ] && ! alive "$legacy_s"'

old="$(role_run check-generation old codex "$review_repo" old)"; owner="$(field "$old" session)"
# A second coordinator reused the same name after the first process exited.
tmux kill-session -t "=$owner"
new="$(HATCH_LEDGER="$W/foreign.tsv" role_run check-generation new codex "$review_repo" new)"
led close "$owner" >/dev/null
check "close cannot silence a replacement generation" '[ -z "$(tmux show-options -t "$owner" -qv @hatch_closed)" ]'
"$BIN/hatch-end" "$owner" >/dev/null 2>&1; rc=$?
check "end cannot kill a replacement generation" '[ "$rc" = 3 ] && alive "$owner"'

r="$(HATCH_CODEX_CMD="env HATCH_FAKE_NO_STATUS=1 $HATCH_CODEX_CMD" role_run check-idle no-status codex "$review_repo" x)"; rs="$(field "$r" session)"; led close "$rs" >/dev/null
sweep="$(HATCH_ROLE_IDLE_MIN=0 "$BIN/hatch-reap" --dry-run)"
check "reap spares roles without activity records" '! grep -Fq "local/$rs " <<<"$sweep"'

long="$(printf '%039d' 0 | tr 0 a)-bc"
r="$(role_run check-id "$long" codex "$review_repo" task)"
ident="$(field "$r" task)"
check "canonical task id is stable after truncation" '[ "$ident" = "${long%%-*}" ] && [ "$(led lookup "$(field "$r" session)" local | cut -f10)" = "$ident" ]'
for delim in tab newline; do
  root="$W/bad"$'\t'root; [ "$delim" = tab ] || root="$W/bad"$'\n'root
  HATCH_OUT_ROOT="$root" role_run "check-$delim" a codex "$review_repo" x >/dev/null 2>&1; rc=$?
  check "reject $delim in out path before launch" '[ "$rc" -ne 0 ] && ! alive "codex-check-$delim-research"'
done
space_out="$W/out with spaces"
r="$(HATCH_OUT_ROOT="$space_out" role_run check-space a codex "$review_repo" x)"
r="$(HATCH_OUT_ROOT="$space_out" role_run check-space b codex "$review_repo" y)"
check "out paths with spaces survive continuation" 'grep -Fq "state=continued" <<<"$r" && grep -Fq "$space_out/" <<<"$r"'

# Hold the actual kernel lock in an independent fixture process; it exits on its own.
perl -e 'open F, ">>", $ARGV[0] or die; flock F,2; open R,">",$ARGV[1]; close R; sleep 2' "$HATCH_LEDGER.lifecycle" "$W/locked" & holder=$!
waitfor '[ -f "$W/locked" ]'
msg="$(HATCH_LOCK_TIMEOUT=0 "$BIN/hatch-ledger" close "$rs" 2>&1)"; rc=$?; wait "$holder"
check "contended lifecycle lock has a bounded refusal" '[ "$rc" = 3 ] && grep -q "lock busy" <<<"$msg"'
if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ] && command -v zsh >/dev/null; then
  r="$(role_run check-zsh test-zsh --host "$HATCH_TEST_HOST" codex "$review_repo" first)"
  rs="$(field "$r" session)"
  HATCH_TEST_LOGIN_SHELL=zsh led close test-zsh >/dev/null
  legacy_zsh="$("$BIN/hatch-launch" --host "$HATCH_TEST_HOST" --force --slug zzt-zsh-legacy codex "$review_repo" legacy)"
  legacy_zsh_session="$(field "$legacy_zsh" session)"
  HATCH_TEST_LOGIN_SHELL=zsh led close "$legacy_zsh_session" >/dev/null
  check "remote close quotes exact targets for zsh" '[ "$("$W/remote-bin/tmux" show-options -t "$rs" -qv @hatch_closed)" = 1 ] && [ "$("$W/remote-bin/tmux" show-options -t "$legacy_zsh_session" -qv @hatch_closed)" = 1 ]'
fi

echo "== P1 review: cross-generation and compatibility controls"
# Scope the sweep to one stale ledger and give its same-named replacement a real idle reading.
awk -F'\t' -v s="$owner" 'NR==1 || $4==s' "$HATCH_LEDGER" >"$W/stale.tsv"
pid="$(tmux display-message -p -t "$owner" '#{pane_pid}')"
if [ -r "/proc/$pid/stat" ]; then start="$(sed 's/.*) //' "/proc/$pid/stat" | cut -d' ' -f20)"
else start="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$pid" | awk '{$1=$1; print}')"; fi
jq -n --argjson pid "$pid" --arg cwd "$review_repo" --arg start "$start" \
  '{kind:"interactive",pid:$pid,cwd:$cwd,procStart:$start,status:"idle",sessionId:"replacement",updatedAt:1}' >"$CLAUDE_CONFIG_DIR/sessions/replacement.json"
HATCH_LEDGER="$W/stale.tsv" HATCH_ROLE_IDLE_MIN=0 "$BIN/hatch-reap" >/dev/null 2>&1
check "reap cannot kill a replacement with confirmed idle status" 'alive "$owner"'
rm "$CLAUDE_CONFIG_DIR/sessions/replacement.json"

legacy_r="$("$BIN/hatch-launch" --readonly --slug legacy-history-review claude "$review_repo" legacy)"
legacy_s="$(field "$legacy_r" session)"; led close "$legacy_s" >/dev/null
"$BIN/hatch-launch" --role review --repo legacy-history --fresh --task r claude "$review_repo" review >/dev/null 2>&1; rc=$?
renamed="$("$BIN/hatch-launch" --role review --repo explicit-history --task r claude "$review_repo" review)"
check "legacy history remains accessible with an explicit role repo name" '[ "$rc" = 3 ] && [ "$(field "$renamed" state)" = created ] && [ "$(led status "$legacy_s" local)" = closed ]'
counterpart="$("$BIN/hatch-launch" --role review --repo explicit-history --task r codex "$review_repo" review)"
check "full review session names select each agent despite a shared slug" '[ "$(led lookup "$(field "$renamed" session)" local | cut -f2)" = claude/ro ] && [ "$(led lookup "$(field "$counterpart" session)" local | cut -f2)" = codex ]'

if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ]; then
  r="$(HATCH_CODEX_CMD="env HATCH_FAKE_NO_STATUS=1 $HATCH_CODEX_CMD" role_run check-boundary "$long" --host "$HATCH_TEST_HOST" codex "$review_repo" boundary)"
  ident="$(field "$r" task)"; remote_s="$(field "$r" session)"
  check "remote advertised task id closes the reserved ledger id" '[ "$ident" = "${long%%-*}" ] && [ "$(led lookup "$remote_s" "$HATCH_TEST_HOST" | cut -f10)" = "$ident" ] && led close --task "$ident" >/dev/null && [ "$(led status "$remote_s" "$HATCH_TEST_HOST")" = closed ]'
fi

if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ]; then
  sweep="$(HATCH_TEST_BAD_LIST="$remote_s" HATCH_ROLE_IDLE_MIN=0 "$BIN/hatch-reap" --dry-run)"
  check "failed activity lookup cannot authorize remote idle reap" '! grep -Fq "$HATCH_TEST_HOST/$remote_s " <<<"$sweep"'
fi
if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ]; then
  awk -F'\t' -v s="$remote_s" -v h="$HATCH_TEST_HOST" 'NR==1 || ($4==s && $2==h)' "$HATCH_LEDGER" >"$W/stale-activity.tsv"
  HATCH_TEST_STALE_IDLE="$remote_s" HATCH_ROLE_IDLE_MIN=0 HATCH_LEDGER="$W/stale-activity.tsv" "$BIN/hatch-reap" >/dev/null 2>&1
  check "reap rechecks host activity at shutdown" '"$W/remote-bin/tmux" has-session -t "=$remote_s"'
fi

# A metadata failure before sending leaves the previous round in place.
r="$(role_run check-prewrite first codex "$review_repo" first)"; pre_out="$(field "$r" out)"; pre_s="$(field "$r" session)"
led close "$pre_s" >/dev/null
[ ! -f "$pre_out/meta.json.lock" ] || mv "$pre_out/meta.json.lock" "$W/spare-lock"
mkdir "$pre_out/meta.json.lock"
role_run check-prewrite next codex "$review_repo" prewrite-sentinel >/dev/null 2>&1; rc=$?
check "metadata write failure leaves the closed round intact without sending" '[ "$rc" -ne 0 ] && [ "$(led status "$pre_s" local)" = closed ] && [ "$(tmux show-options -t "$pre_s" -qv @hatch_task)" = first ]'
rmdir "$pre_out/meta.json.lock"
r="$(role_run check-prewrite next codex "$review_repo" prewrite-sentinel)"
check "repairing metadata lets the next round proceed" '[ "$(field "$r" round)" = 2 ] && [ "$(led status "$pre_s" local)" = open ]'

r="$(role_run check-rows a codex "$review_repo" first)"; rows_s="$(field "$r" session)"; rows_out="$(field "$r" out)"
role_run check-rows b codex "$review_repo" second >/dev/null
role_run check-rows a codex "$review_repo" correction >/dev/null
rows="$(awk -F'\t' -v s="$rows_s" -v o="$rows_out" '$4==s && $6==o { print $11,$14,$7 }' "$HATCH_LEDGER")"
check "launching A B A supersedes only the first A in one generation" '[ "$rows" = "$(printf "1 a closed\n2 b open\n3 a open")" ]'

for activity in busy waiting; do
  r="$(role_run "check-gate-$activity" first claude "$review_repo" first)"
  rs="$(field "$r" session)"; gate_out="$(field "$r" out)"
  waitfor '[ -s "$gate_out/report.md" ]'
  pid="$(tmux display-message -p -t "$rs" '#{pane_pid}')"
  if [ -r "/proc/$pid/stat" ]; then start="$(sed 's/.*) //' "/proc/$pid/stat" | cut -d' ' -f20)"
  else start="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$pid" | awk '{$1=$1; print}')"; fi
  reg="$CLAUDE_CONFIG_DIR/sessions/fake-$pid.json"
  jq -n --argjson pid "$pid" --arg cwd "$review_repo" --arg start "$start" --arg activity "$activity" \
    '{kind:"interactive",pid:$pid,cwd:$cwd,procStart:$start,status:$activity,sessionId:"gate",updatedAt:1}' >"$reg"
  role_run "check-gate-$activity" next claude "$review_repo" next >/dev/null 2>&1; rc=$?
  check "completed Stop cannot override $activity activity" '[ "$rc" = 3 ] && [ "$(led lookup "$rs" | cut -f6)" = 1 ]'
  rm "$reg"
done
