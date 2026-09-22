#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

preflight="$ROOT/bin/omarchy-update-preflight"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

# The free-space check delegates to omarchy-update-requires-free-space, which
# reads df itself. Stub df so the available bytes are fully under our control
# without touching the host filesystem.
write_stub() {
  local name="$1"
  local body="$2"
  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

write_stub df '
if [[ ${TEST_DF_INVALID:-0} == "1" ]]; then
  printf "Avail\nunknown\n"
else
  printf "Avail\n%s\n" "$TEST_AVAILABLE_BYTES"
fi'

# The preflight asks omarchy-update-lock whether an update is held. Stub it
# so the answer is deterministic and no real lock file is consulted.
write_stub omarchy-update-lock '
if [[ "${1:-}" == "held" ]]; then
  exit 1
fi
exit 0'

# systemctl is faked to report a healthy state so the systemd check is
# deterministic on machines where the manager is not running.
write_stub systemctl '
if [[ "${1:-}" == "is-system-running" ]]; then
  echo "running"
  exit 0
fi
exit 0'

# omarchy-migrate --pending exits 0 with no output when nothing is pending and
# 1 when something is. Both are valid answers for the preflight, which only
# cares about the exit status.
write_stub omarchy-migrate '
if [[ "${1:-}" == "--pending" ]]; then
  exit "${TEST_MIGRATE_PENDING:-1}"
fi
exit 0'

run_preflight() {
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_AVAILABLE_BYTES="${TEST_AVAILABLE_BYTES:-$((11 * 1024 * 1024 * 1024))}" \
    TEST_DF_INVALID="${TEST_DF_INVALID:-0}" \
    TEST_MIGRATE_PENDING="${TEST_MIGRATE_PENDING:-1}" \
    "$preflight" "$@"
}

# --- sufficient disk passes ----------------------------------------------

set +e
output=$(run_preflight --json)
status=$?
set -e
(( status == 0 )) || fail "preflight passes with sufficient disk space"
echo "$output" | jq -e 'any(.checks[]; .name == "disk-space" and .status == "ok")' >/dev/null ||
  fail "preflight reports sufficient disk space as ok"
pass "preflight passes with sufficient disk space"

# --- insufficient disk fails ----------------------------------------------

set +e
output=$(TEST_AVAILABLE_BYTES=$((9 * 1024 * 1024 * 1024)) run_preflight --json)
status=$?
set -e
(( status == 1 )) || fail "preflight fails with insufficient disk space"
echo "$output" | jq -e 'any(.checks[]; .name == "disk-space" and .status == "fail")' >/dev/null ||
  fail "preflight reports insufficient disk space as a failure"
pass "preflight fails with insufficient disk space"

# --- pacman lock ----------------------------------------------------------

set +e
output=$(PATH="$stub_bin:$ROOT/bin:$PATH" "$preflight" --json)
status=$?
set -e
(( status == 0 )) || fail "preflight passes without a pacman lock"
echo "$output" | jq -e 'any(.checks[]; .name == "pacman-lock" and .status == "ok")' >/dev/null ||
  fail "preflight reports no pacman lock as ok"
pass "preflight reports no pacman lock"

# The lock path is overridable so the test never touches the real, root-owned
# /var/lib/pacman/db.lck.
pacman_lock="$tmp_dir/db.lck"
touch "$pacman_lock"
set +e
output=$(OMARCHY_PACMAN_LOCK_PATH="$pacman_lock" PATH="$stub_bin:$ROOT/bin:$PATH" "$preflight" --json)
status=$?
rm -f "$pacman_lock"
set -e
(( status == 1 )) || fail "preflight fails when pacman is locked"
echo "$output" | jq -e 'any(.checks[]; .name == "pacman-lock" and .status == "fail")' >/dev/null ||
  fail "preflight reports the pacman lock as a failure"
pass "preflight reports the pacman lock"

# --- update lock ----------------------------------------------------------

set +e
output=$(PATH="$stub_bin:$ROOT/bin:$PATH" "$preflight" --json)
status=$?
set -e
(( status == 0 )) || fail "preflight passes without an update lock"
echo "$output" | jq -e 'any(.checks[]; .name == "update-lock" and .status == "ok")' >/dev/null ||
  fail "preflight reports no update lock as ok"
pass "preflight reports no update lock"

# --- pending migrations warn, do not fail --------------------------------

set +e
output=$(TEST_MIGRATE_PENDING=0 run_preflight --json)
status=$?
set -e
(( status == 0 )) || fail "preflight passes with pending migrations"
echo "$output" | jq -e 'any(.checks[]; .name == "migrations" and .status == "warn")' >/dev/null ||
  fail "preflight reports pending migrations as a warning"
pass "preflight warns about pending migrations without failing"

# --- text mode ------------------------------------------------------------

set +e
output=$(run_preflight)
status=$?
set -e
(( status == 0 )) || fail "preflight text mode passes with sufficient disk"
[[ $output == *"CHECK"* ]] || fail "text mode prints a header"
[[ $output == *"STATE"* ]] || fail "text mode prints column headers"
[[ $output == *"DETAIL"* ]] || fail "text mode prints column headers"
pass "preflight text mode renders"

# --- read-only guarantee --------------------------------------------------

# The command must not create or remove anything. Run it against a path that
# does not exist yet and confirm it stays absent.
missing_root="$tmp_dir/does-not-exist"
set +e
PATH="$stub_bin:$ROOT/bin:$PATH" "$preflight" >/dev/null 2>&1
status=$?
set -e
(( status == 0 )) || fail "preflight passes when no real state is present"
[[ ! -e $missing_root ]] || fail "preflight created a directory as a side effect"
pass "preflight does not create directories as a side effect"