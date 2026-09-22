#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

state_export="$ROOT/bin/omarchy-state-export"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

state_dir="$tmp_dir/omarchy"

run_export() {
  XDG_STATE_HOME="$tmp_dir" PATH="$ROOT/bin:$PATH" "$state_export" "$@"
}

# --- empty state directory -----------------------------------------------

mkdir -p "$state_dir"
set +e
output=$(run_export --json)
status=$?
set -e
(( status == 0 )) || fail "state export exits zero with an empty state directory"
echo "$output" | jq -e '.state_dir == "'"$state_dir"'"' >/dev/null ||
  fail "JSON reports the state directory"
echo "$output" | jq -e '.entries == []' >/dev/null ||
  fail "JSON reports no entries for an empty state directory"
pass "state export handles an empty state directory"

# --- multiple state entries ----------------------------------------------

touch "$state_dir/restart-required" "$state_dir/reboot-required"
set +e
output=$(run_export --json)
status=$?
set -e
(( status == 0 )) || fail "state export exits zero with state entries"
echo "$output" | jq -e '.entries | length == 2' >/dev/null ||
  fail "JSON reports two entries"
echo "$output" | jq -e '.entries | index("restart-required")' >/dev/null ||
  fail "JSON includes restart-required"
echo "$output" | jq -e '.entries | index("reboot-required")' >/dev/null ||
  fail "JSON includes reboot-required"
pass "state export lists multiple state entries"

# --- output is sorted and stable -----------------------------------------

set +e
first=$(run_export --json | jq -c '.entries')
second=$(run_export --json | jq -c '.entries')
set -e
[[ $first == "$second" ]] || fail "state export output is stable across runs"
pass "state export output is stable across runs"

# --- text mode -----------------------------------------------------------

set +e
output=$(run_export)
status=$?
set -e
(( status == 0 )) || fail "state export text mode exits zero"
[[ $output == *"state_dir="* ]] || fail "text mode reports the state directory"
[[ $output == *"restart-required"* ]] || fail "text mode lists state entries"
pass "state export text mode renders"

# --- missing state directory --------------------------------------------

rm -rf "$state_dir"
set +e
output=$(run_export --json)
status=$?
set -e
(( status == 0 )) || fail "state export exits zero when the state directory is absent"
echo "$output" | jq -e '.entries == []' >/dev/null ||
  fail "JSON reports no entries when the state directory is absent"
pass "state export handles a missing state directory"

# --- read-only guarantee -------------------------------------------------

# The command must not create the state directory. Run it against a path that
# does not exist yet and confirm it stays absent.
missing_dir="$tmp_dir/not-created"
XDG_STATE_HOME="$missing_dir" PATH="$ROOT/bin:$PATH" "$state_export" >/dev/null 2>&1
[[ ! -e $missing_dir ]] || fail "state export created the state directory"
pass "state export does not create directories as a side effect"