# Sourced by run.sh inside its private tmux server and ledger.
echo "== role ledger: independent tasks, close and reap"
RS=claude-zzt-roles; RS2=codex-zzt-roles
for s in "$RS" "$RS2"; do tmux new-session -d -s "$s" -c "$REPO" "$T/fake-agent"; tmux set-option -t "$s" @hatch_openclaw 1; done
tmux set-option -t "$RS" @hatch_role review; tmux set-option -t "$RS" @hatch_out "$W/out/roles"
tmux set-option -t "$RS2" @hatch_role research; tmux set-option -t "$RS2" @hatch_out "$W/out/roles2"
add_review() { "$BIN/hatch-ledger" add local claude/ro "$RS" zzt-roles "$W/out/roles" e "$1" - review "$2"; }
add_review 1 alpha; add_review 2 beta; add_review 3 alpha
for fixture in roles:3 roles2:1; do
  dir="$W/out/${fixture%:*}"; mkdir -p "$dir"
  printf '{"round":%s}\n' "${fixture#*:}" >"$dir/meta.json"
done
tmux set-option -t "$RS" @hatch_round 3
tmux set-option -t "$RS2" @hatch_round 1
"$BIN/hatch-ledger" add local codex "$RS2" zzt-roles "$W/out/roles2" e 1 - research alpha
"$BIN/hatch-ledger" note "$RS" "verified" >/dev/null
check "note preserves 14 columns including role and task" 'awk -F"\t" -v s="$RS" '\''$4 == s && $11 == 3 { ok = NF == 14 && $13 == "review" && $14 == "alpha" && $9 ~ /verified/ } END { exit !ok }'\'' "$HATCH_LEDGER"'
check "only an earlier round of the same task is superseded" 'awk -F"\t" -v s="$RS" '\''$4 == s { v = v $7; if ($11 == 1 && $9 !~ /superseded/) exit 1 } END { exit v != "closedopenopen" }'\'' "$HATCH_LEDGER"'
check "list --task includes matching rounds across sessions" '[ "$("$BIN/hatch-ledger" list --task alpha | cut -f4,7 | tail -n +2)" = "$(printf "%s\tclosed\n%s\topen\n%s\topen" "$RS" "$RS" "$RS2")" ]'
msg="$("$BIN/hatch-ledger" close alpha verified)"
check "closing a task keeps both role sessions alive" 'alive "$RS" && alive "$RS2" && grep -Fq "role session $RS stays" <<<"$msg"'
check "closed mark only on the session with no remaining task" '[ -z "$(tmux show-options -t "$RS" -qv @hatch_closed)" ] && [ "$(tmux show-options -t "$RS2" -qv @hatch_closed)" = 1 ]'
"$BIN/hatch-end" "$RS" >/dev/null 2>&1; rc=$?
check "an older open task blocks hatch-end and reap" '[ "$rc" -eq 3 ] && ! HATCH_ROLE_IDLE_MIN=0 "$BIN/hatch-reap" --dry-run | grep -Fq "local/$RS "'
"$BIN/hatch-ledger" close beta >/dev/null
# Feed the regular hatch-list status reader a registry entry for the fake pane.
pid="$(tmux display-message -p -t "$RS" '#{pane_pid}')"
if [ -r "/proc/$pid/stat" ]; then
  started="$(sed 's/.*) //' "/proc/$pid/stat" | cut -d' ' -f20)"
else
  started="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$pid" | awk '{$1=$1; print}')"
fi
set_fake_activity() {
  jq -n --argjson pid "$pid" --arg cwd "$REPO" --arg start "$started" --arg activity "$1" \
    '{kind:"interactive",pid:$pid,cwd:$cwd,procStart:$start,status:$activity,sessionId:"test-sid",updatedAt:1}' >"$CLAUDE_CONFIG_DIR/sessions/test.json"
 }
set_fake_activity idle
sweep="$("$BIN/hatch-reap" --dry-run)"; immediate="$(HATCH_ROLE_IDLE_MIN=0 "$BIN/hatch-reap" --dry-run)"
check "closed role reviews survive until their idle period elapses" 'alive "$RS" && ! grep -Fq "local/$RS " <<<"$sweep" && grep -Fq "local/$RS " <<<"$immediate"'
# The latest round closed long ago, but the older open task was only just closed.
awk -F'\t' -v OFS='\t' -v s="$RS" '$4 == s && $11 == 3 { $10 = 1 } { print }' "$HATCH_LEDGER" >"$W/aged" && mv "$W/aged" "$HATCH_LEDGER"
check "idle age uses the most recent close across rounds" '! "$BIN/hatch-reap" --dry-run | grep -Fq "local/$RS "'

for activity in busy waiting unknown; do
  set_fake_activity "$activity"
  listing="$("$BIN/hatch-list")"; sweep="$(HATCH_ROLE_IDLE_MIN=0 "$BIN/hatch-reap" --dry-run)"
  state="$activity"; [ "$state" = busy ] && state=working; [ "$state" = unknown ] && state="?"
  check "role session reported as $state is spared even at zero grace" 'grep -Fq "$state" <<<"$listing" && ! grep -Fq "local/$RS " <<<"$sweep"'
done
rm "$CLAUDE_CONFIG_DIR/sessions/test.json"

echo "== existing 12-column ledger: list, note, close, continue"
old="$W/old.tsv"; old_out="$W/out/old"; old_session=claude-zzt-old
mkdir -p "$old_out"; git -C "$W" init -q "$W/old-repo"
jq -n --arg cwd "$W/old-repo" '{cwd:$cwd,agent_session_id:"old-sid"}' >"$old_out/meta.json"
head -1 "$HATCH_LEDGER" | cut -f1-12 >"$old"
printf '2026-11-18T12:00\tlocal\tclaude\t%s\tzzt-old\t%s\topen\tlegacy expect\t\t\t1\t-\n' "$old_session" "$old_out" >>"$old"
legacy() { HATCH_LEDGER="$old" "$BIN/hatch-ledger" "$@"; }
check "old ledger header migrates on list; original row stays readable" 'legacy list | grep -q "legacy expect" && [ "$(head -1 "$old" | cut -f13,14)" = "$(printf "role\ttask")" ]'
legacy note zzt-old "legacy note" >/dev/null; legacy close zzt-old >/dev/null
check "old ledger still accepts note and close" '[ "$(legacy status "$old_session")" = closed ] && legacy show "$old_session" | grep -q "legacy note"'
r="$(HATCH_LEDGER="$old" "$BIN/hatch-launch" --continue zzt-old again)"
check "old ledger resumes an unroled conversation" '[ "$(field "$r" state)" = resumed ] && [ "$(field "$r" round)" = 2 ] && [ "$(field "$r" out)" = "$old_out" ] && [ -z "$(legacy lookup "$old_session" | cut -f9-10 | tr -d "\t")" ]'

echo "== role launch: creation, continuation, access mode, resume and fresh"
repo="$W/zzt-project"; git init -q "$repo"
launch_role() { "$BIN/hatch-launch" --role "$1" --task "$2" "${@:3}"; }
r="$(launch_role impl a codex "$repo" 'implement the first task')"; impl="$(field "$r" session)"; impl_out="$(field "$r" out)"
check "implementation uses the repository basename and mode" '[ "$impl" = codex-zzt-project-impl ] && [ "$(field "$r" mode)" = write ] && [ "$(field "$r" task)" = a ] && [ "$(field "$r" role)" = impl ]'
check "role rules available to the first round" 'cmp -s "$T/../roles/impl.md" "$impl_out/ROLE.md" && grep -Fq "$impl_out/ROLE.md" "$FAKELOG"'
r="$(launch_role impl b codex "$repo" 'implement the second task')"
check "second task shares the live session and out" '[ "$(field "$r" session)" = "$impl" ] && [ "$(field "$r" out)" = "$impl_out" ] && [ "$(field "$r" round)" = 2 ] && [ "$(field "$r" state)" = continued ] && ! alive "$impl-2"'
check "both prompts name their round-specific report" 'waitfor "[ -f \"$impl_out/report-2.md\" ]" && [ -f "$impl_out/report.md" ] && grep -Fq "Round 2 of the impl session for zzt-project." "$FAKELOG"'
check "tmux and metadata identify the new task" '[ "$(tmux show-options -t "$impl" -qv @hatch_role)" = impl ] && [ "$(tmux show-options -t "$impl" -qv @hatch_task)" = b ] && jq -e '\''.role == "impl" and [.rounds[].task] == ["a","b"]'\'' "$impl_out/meta.json" >/dev/null'
launch_role impl new --fresh codex "$repo" 'fresh while open' >/dev/null 2>&1; rc=$?
check "fresh refuses open tasks" '[ "$rc" -eq 3 ] && alive "$impl"'
"$BIN/hatch-ledger" close b >/dev/null
launch_role impl new --fresh codex "$repo" 'older task still open' >/dev/null 2>&1; rc=$?
check "fresh checks older open rounds" '[ "$rc" -eq 3 ] && alive "$impl"'
"$BIN/hatch-ledger" close a >/dev/null
jq '.agent_session_id="role-sid"' "$impl_out/meta.json" >"$W/meta" && mv "$W/meta" "$impl_out/meta.json"
"$BIN/hatch-end" "$impl" >/dev/null
r="$(launch_role impl c codex "$repo" 'third task')"
check "ended implementation resumes round three in its original out" '[ "$(field "$r" state)" = resumed ] && [ "$(field "$r" round)" = 3 ] && [ "$(field "$r" out)" = "$impl_out" ] && grep -q "^ARGV: resume .*role-sid" "$FAKELOG" && [ -f "$impl_out/report-3.md" ]'
r="$("$BIN/hatch-launch" --continue "$impl" again)"
check "explicit continue inherits the role and task" '[ "$(field "$r" round)" = 4 ] && [ "$(field "$r" task)" = c ] && [ "$(field "$r" role)" = impl ]'
r="$("$BIN/hatch-launch" --continue "$impl" --task 'Task D' again)"
check "explicit continue accepts a sanitized task id" '[ "$(field "$r" task)" = task-d ] && [ "$(field "$r" round)" = 5 ]'

review="$(launch_role review rev codex "$repo" 'codex role review')"; research="$(launch_role research res codex "$repo" 'codex role research')"
review_out="$(field "$review" out)"; research_out="$(field "$research" out)"
check "Codex review and research can write alongside implementation" '[ "$(field "$review" mode)" = write ] && [ "$(field "$research" mode)" = write ] && grep -Fq "ARGV: --add-dir $review_out codex role review" "$FAKELOG" && grep -Fq "ARGV: --add-dir $research_out codex role research" "$FAKELOG"'
review2="$(launch_role review rev claude "$repo" 'claude role review')"
check "Claude review uses plan mode and a separate out" '[ "$(field "$review2" mode)" = read ] && [ "$(field "$review2" out)" != "$review_out" ] && grep -Fq "ARGV: --permission-mode plan claude role review" "$FAKELOG"'
"$BIN/hatch-ledger" close rev >/dev/null
check "closing a shared review task preserves both conversations" 'alive "$(field "$review" session)" && alive "$(field "$review2" session)"'
m="$(launch_role impl another --repo second codex "$repo" 'second impl' 2>&1)"; rc=$?
check "another implementation is refused with role continuation guidance" '[ "$rc" -eq 3 ] && grep -Fq -- "--role impl --task" <<<"$m"'
"$BIN/hatch-launch" --slug zzt-old-writer codex "$repo" 'legacy writer' >/dev/null 2>&1; rc=$?
check "a legacy writer also conflicts with implementation" '[ "$rc" -eq 3 ]'
launch_role impl another --repo occupied codex "$REPO" 'impl against legacy' >/dev/null 2>&1; rc=$?
check "implementation conflicts with an existing legacy writer" '[ "$rc" -eq 3 ]'

waitfor '[ -s "$impl_out/report-5.md" ]'
"$BIN/hatch-ledger" close "$impl" >/dev/null
r="$(launch_role impl new --fresh codex "$repo" 'new conversation')"; fresh_out="$(field "$r" out)"
check "fresh starts at round one with a new out and history" '[ "$(field "$r" state)" = created ] && [ "$(field "$r" round)" = 1 ] && [ "$fresh_out" != "$impl_out" ] && jq -e '\''[.rounds[].task] == ["new"] and .agent_session_id == null'\'' "$fresh_out/meta.json" >/dev/null'
check "fresh preserves prior reports and records retirement" '[ -f "$impl_out/report-3.md" ] && awk -F"\t" -v o="$impl_out" '\''$6 == o && $11 == 5 && $9 ~ /retired/ { ok=1 } END { exit !ok }'\'' "$HATCH_LEDGER"'

tmux new-session -d -s codex-zzt-orphan-research "$T/fake-agent"
launch_role research orphan --repo zzt-orphan codex "$repo" collision >/dev/null 2>&1; rc=$?
check "untracked session name collision is refused without a suffix" '[ "$rc" -eq 3 ] && alive codex-zzt-orphan-research && ! alive codex-zzt-orphan-research-2'

# Two coordinators must allocate distinct round numbers for the same conversation.
launch_role research x codex "$repo" parallel-x >"$W/rx" & px=$!
launch_role research y codex "$repo" parallel-y >"$W/ry" & py=$!
wait "$px"; rx=$?; wait "$py"; ry=$?
check "parallel launches append consecutive rounds to one out" '[ "$rx" -eq 0 ] && [ "$ry" -eq 0 ] && jq -e '\''[.rounds[].round] == [1,2,3] and ([.rounds[].task] | sort) == ["res","x","y"]'\'' "$research_out/meta.json" >/dev/null'

if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ]; then
  echo "== role identity and retirement across two hosts"
  loop="$HATCH_TEST_HOST"
  remote="$(launch_role impl remote-a --host "$loop" codex "$repo" 'remote round 1')"
  remote_out="$(field "$remote" out)"
  check "same role name on another host starts its own conversation" '[ "$(field "$remote" session)" = "$impl" ] && [ "$(field "$remote" round)" = 1 ] && [ "$remote_out" != "$fresh_out" ] && [ -f "$remote_out/meta.json" ]'
  r="$(launch_role impl local-b codex "$repo" 'local follow-up')"
  check "default host uses its local row even when remote row was newer" '[ "$(field "$r" out)" = "$fresh_out" ] && [ "$(field "$r" round)" = 2 ]'
  r="$(launch_role impl remote-b --host "$loop" codex "$repo" 'remote follow-up')"
  check "remote host continues through the coordinator ledger" '[ "$(field "$r" out)" = "$remote_out" ] && [ "$(field "$r" round)" = 2 ] && [ ! -f "$W/remote-ledger.tsv" ]'
  waitfor '[ -s "$remote_out/report-2.md" ]'
  "$BIN/hatch-ledger" close remote-a >/dev/null; "$BIN/hatch-ledger" close remote-b >/dev/null
  r="$(launch_role impl remote-c --host "$loop" --fresh codex "$repo" 'retire remote only')"
  check "fresh retires only the requested host" '[ "$(field "$r" round)" = 1 ] && [ "$(field "$r" out)" != "$remote_out" ] && [ "$("$BIN/hatch-ledger" status "$impl" local)" = open ] && [ "$(tmux show-options -t "$impl" -qv @hatch_out)" = "$fresh_out" ]'
  "$W/remote-bin/tmux" set-option -g @codex_session_prefix alt-
  r="$(launch_role research prefixed --host "$loop" codex "$repo" 'non-default prefix')"
  r2="$(launch_role research prefixed --host "$loop" codex "$repo" 'prefixed follow-up')"
  check "role lookup respects a host-specific tmux prefix" '[ "$(field "$r" session)" = alt-zzt-project-research ] && [ "$(field "$r2" state)" = continued ] && [ "$(field "$r" out)" = "$(field "$r2" out)" ]'
fi

echo "== role key collisions and numeric task ids"
same="$W/other/zzt-project"; mkdir -p "$same"; git init -q "$same"
launch_role impl wrong codex "$same" 'another checkout' >/dev/null 2>&1; rc=$?
check "same basename in another checkout cannot redirect a role round" '[ "$rc" -eq 3 ] && [ "$(tmux show-options -t "$impl" -qv @hatch_out)" = "$fresh_out" ]'
r="$(cd "$same" && launch_role research 01 --repo alternate codex . 'keep leading zeroes')"
alternate="$(field "$r" session)"
r="$(launch_role research 1 --repo alternate codex "$same" 'distinct numeric id')"
"$BIN/hatch-ledger" close 1 >/dev/null
check "numeric task ids retain leading zeroes on add, close and list" '[ "$("$BIN/hatch-ledger" status "$alternate" local)" = open ] && [ "$("$BIN/hatch-ledger" list --task 01 | tail -n +2 | cut -f7,12)" = "$(printf "open\t01")" ]'
git init -q "$W/zzt-dot"
r="$(cd "$W/zzt-dot" && launch_role review dotted claude . 'basename from cwd')"
check "role launch from a relative dot directory resolves its repository name" '[ "$(field "$r" session)" = claude-zzt-dot-review ]'

echo "== legacy options and an explicitly requested role worktree"
work="$(launch_role impl wt --worktree --branch role-topic --repo zzt-tree codex "$REPO" 'use a worktree')"
wout="$(field "$work" out)"; tree="$(jq -r .cwd "$wout/meta.json")"
continued="$(launch_role impl wt --repo zzt-tree codex "$REPO" 'continue in the worktree')"
check "requested worktree is retained when continuing from the source directory" '[ "$tree" = "$REPO-wt/role-topic" ] && [ "$(git -C "$tree" branch --show-current)" = role-topic ] && [ "$(field "$continued" state)" = continued ] && [ "$(field "$continued" out)" = "$wout" ]'
pop_repo="$W/popup"; mkdir "$pop_repo"
. "$T/../../scripts/helpers.sh"
popup="codex-$(session_hash "$pop_repo")"; tmux new-session -d -s "$popup" -c "$pop_repo" "$T/fake-agent"
r="$("$BIN/hatch-launch" --reuse --any-dir codex "$pop_repo" 'legacy reuse')"
check "legacy --reuse and --any-dir still select the popup session" '[ "$(field "$r" session)" = "$popup" ] && [ "$(field "$r" state)" = reused ]'

echo "== fresh checks ownership and prepares the replacement before ending a live conversation"
"$BIN/hatch-ledger" close "$alternate" >/dev/null
original_out="$(tmux show-options -t "$alternate" -qv @hatch_out)"
tmux set-option -t "$alternate" @hatch_out "$W/foreign-out"
launch_role research fresh --repo alternate --fresh codex "$same" 'foreign session' >/dev/null 2>&1; rc=$?
check "fresh refuses a live session whose out differs from its ledger row" '[ "$rc" -eq 3 ] && alive "$alternate" && [ "$(tmux show-options -t "$alternate" -qv @hatch_out)" = "$W/foreign-out" ]'
tmux set-option -t "$alternate" @hatch_out "$original_out"
HATCH_OUT_ROOT="$HATCH_LEDGER" launch_role research fresh --repo alternate --fresh codex "$same" 'unavailable out root' >/dev/null 2>&1; rc=$?
check "an unavailable new out preserves the previous live role session" '[ "$rc" -ne 0 ] && alive "$alternate" && [ "$(tmux show-options -t "$alternate" -qv @hatch_out)" = "$original_out" ]'
