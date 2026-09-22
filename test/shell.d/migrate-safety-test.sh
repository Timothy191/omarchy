#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migrate="$ROOT/bin/omarchy-migrate"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

test_root="$tmp_dir/omarchy"
test_home="$tmp_dir/home"
stub_bin="$tmp_dir/bin"
state_dir="$test_home/.local/state/omarchy/migrations"
mkdir -p "$test_root/migrations" "$test_home" "$stub_bin"

# omarchy-migrate dismisses a login-time notification at the end. Stub it so
# the test does not depend on the real notification helper.
cat >"$stub_bin/omarchy-notification-dismiss" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/omarchy-notification-dismiss"

run_migrate() {
  HOME="$test_home" \
  OMARCHY_PATH="$test_root" \
  TEST_CALLS="$tmp_dir/calls" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$migrate" "$@"
}

write_migration() {
  local name="$1"
  local body="$2"
  cat >"$test_root/migrations/$name" <<SH
$body
SH
  chmod +x "$test_root/migrations/$name"
}

# --- successful migration writes a marker --------------------------------

write_migration "100-success.sh" 'echo "success migration ran" >>"$TEST_CALLS"'

: >"$tmp_dir/calls"
set +e
run_migrate >/dev/null
status=$?
set -e
(( status == 0 )) || fail "migrate exits zero when every migration succeeds"
grep -q "success migration ran" "$tmp_dir/calls" || fail "migrate ran the success migration"
[[ -f "$state_dir/100-success.sh" ]] || fail "migrate wrote the success marker"
pass "successful migration writes a completion marker"

# --- a completed migration is not run again ------------------------------

calls_before=$(wc -l < "$tmp_dir/calls")
set +e
run_migrate >/dev/null
status=$?
set -e
(( status == 0 )) || fail "migrate exits zero when nothing is pending"
calls_after=$(wc -l < "$tmp_dir/calls")
(( calls_after == calls_before )) || fail "migrate reran completed migrations"
pass "completed migrations are not run again"

set +e
run_migrate --pending >/dev/null
status=$?
set -e
(( status != 0 )) || fail "migrate --pending exits non-zero when nothing is pending"
pass "migrate --pending reports no pending migrations"

# --- --pending lists unmarked migrations ---------------------------------

rm -rf "$state_dir"
write_migration "100-success.sh" 'echo "success migration ran" >>"$TEST_CALLS"'
write_migration "200-failure.sh" 'echo "boom" >&2; exit 3'

: >"$tmp_dir/calls"
set +e
pending=$(run_migrate --pending)
status=$?
set -e
(( status == 0 )) || fail "migrate --pending exits zero when migrations are pending"
grep -q '^100-success\.sh$' <<<"$pending" || fail "migrate --pending lists the unmarked migration"
grep -q '^200-failure\.sh$' <<<"$pending" || fail "migrate --pending lists the failing migration"
pass "migrate --pending lists unmarked migrations"

# --- a failed migration leaves no marker and aborts -----------------------

set +e
run_migrate >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "migrate exits non-zero when a migration fails"
grep -q "success migration ran" "$tmp_dir/calls" || fail "migrate ran the success migration"
[[ ! -f "$state_dir/200-failure.sh" ]] ||
  fail "migrate wrote a marker for a migration that failed"
pass "failed migration leaves no completion marker"

# --- the failed migration is retriable -----------------------------------

set +e
run_migrate >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "migrate retries the failed migration"
pass "failed migration is retried on the next run"

# --- after the failure is fixed, the marker is written atomically ---------

# Replace the failing migration with one that succeeds. The marker is written
# via a temp file and a rename, so it must appear all at once.
write_migration "200-failure.sh" 'echo "fixed migration ran" >>"$TEST_CALLS"'

set +e
run_migrate >/dev/null
status=$?
set -e
(( status == 0 )) || fail "migrate exits zero after the failing migration is fixed"
grep -q "fixed migration ran" "$tmp_dir/calls" || fail "migrate ran the fixed migration"
[[ -f "$state_dir/200-failure.sh" ]] || fail "migrate wrote the marker after the fix"
pass "fixed migration writes its marker"

# --- the marker is not present mid-run -----------------------------------

# A migration that sleeps must not have its marker written until it finishes.
write_migration "300-sleep.sh" 'sleep 0.2; echo "slept" >>"$TEST_CALLS"'
rm -rf "$state_dir"
: >"$tmp_dir/calls"
set +e
( run_migrate >/dev/null 2>&1 ) &
migrate_pid=$!
sleep 0.05
[[ ! -f "$state_dir/300-sleep.sh" ]] ||
  fail "the marker is not written while the migration is still running"
wait "$migrate_pid"
status=$?
set -e
(( status == 0 )) || fail "migrate exits zero after the sleeping migration"
[[ -f "$state_dir/300-sleep.sh" ]] || fail "migrate wrote the marker after the migration finished"
pass "the marker appears only after the migration succeeds"