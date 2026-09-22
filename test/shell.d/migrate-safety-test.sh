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

# A migration that succeeds writes its marker; a failing one must not.
cat >"$test_root/migrations/100-success.sh" <<'SH'
echo "success migration ran" >>"$TEST_CALLS"
SH
cat >"$test_root/migrations/200-failure.sh" <<'SH'
echo "failure migration ran" >>"$TEST_CALLS"
echo "boom" >&2
exit 3
SH

: >"$tmp_dir/calls"

# --- successful migration writes a marker --------------------------------

set +e
run_migrate >/dev/null
status=$?
set -e
(( status == 0 )) || fail "migrate exits zero when every migration succeeds"
grep -q "success migration ran" "$tmp_dir/calls" || fail "migrate ran the success migration"
[[ -f "$state_dir/100-success.sh" ]] || fail "migrate wrote the success marker"
pass "successful migration writes a completion marker"

# --- a failed migration leaves no marker and aborts -----------------------

set +e
run_migrate >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "migrate exits non-zero when a migration fails"
grep -q "failure migration ran" "$tmp_dir/calls" || fail "migrate ran the failing migration"
[[ ! -f "$state_dir/200-failure.sh" ]] ||
  fail "migrate wrote a marker for a migration that failed"
pass "failed migration leaves no completion marker"

# --- the failed migration is retriable -----------------------------------

set +e
run_migrate >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "migrate retries the failed migration"
grep -q "failure migration ran" "$tmp_dir/calls" || fail "migrate retried the failing migration"
pass "failed migration is retried on the next run"

# --- --pending lists unmarked migrations ---------------------------------

set +e
pending=$(run_migrate --pending)
status=$?
set -e
(( status == 0 )) || fail "migrate --pending exits zero when migrations are pending"
grep -q '^200-failure\.sh$' <<<"$pending" || fail "migrate --pending lists the failed migration"
pass "migrate --pending lists unmarked migrations"

# --- after the failure is fixed, the marker is written atomically ---------

# Replace the failing migration with one that succeeds. The marker is written
# via a temp file and a rename, so it must appear all at once.
cat >"$test_root/migrations/200-failure.sh" <<'SH'
echo "fixed migration ran" >>"$TEST_CALLS"
SH

set +e
run_migrate >/dev/null
status=$?
set -e
(( status == 0 )) || fail "migrate exits zero after the failing migration is fixed"
grep -q "fixed migration ran" "$tmp_dir/calls" || fail "migrate ran the fixed migration"
[[ -f "$state_dir/200-failure.sh" ]] || fail "migrate wrote the marker after the fix"
pass "fixed migration writes its marker"

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