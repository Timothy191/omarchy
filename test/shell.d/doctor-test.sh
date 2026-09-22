#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

doctor="$ROOT/bin/omarchy-doctor"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# A fake Omarchy tree gives the command somewhere to look without touching the
# real one. It is empty on purpose: the directory-presence checks then report
# the expected failures, which is the case we are most interested in here.
fake_root="$tmp_dir/omarchy"
mkdir -p "$fake_root"

# A stub bin that satisfies the required-command checks without touching the
# host. systemctl is faked to report a healthy state so the systemd check is
# deterministic on machines where the manager is not running.
stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
if [[ "${1:-}" == "Q" && "${2:-}" == "omarchy" ]]; then
  exit 0
fi
exit 127
SH
cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
if [[ "${1:-}" == "is-system-running" ]]; then
  echo "running"
  exit 0
fi
exit 0
SH
cat >"$stub_bin/git" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/pacman" "$stub_bin/systemctl" "$stub_bin/git"

# The command itself shells out to sed, grep, sort, find and basename for its
# JSON escaping and ordering. Link those in so the stub PATH is self-contained
# and the checks for missing Omarchy commands stay real.
for tool in sed grep sort find basename; do
  ln -sf "$(command -v "$tool")" "$stub_bin/$tool"
done

# An empty stub bin, for the "missing required command" case. Only the tools
# the command itself needs to run are linked in; the required Omarchy commands
# stay missing so the failure checks are real.
empty_stub="$tmp_dir/empty-bin"
mkdir -p "$empty_stub"
for tool in sed grep sort find basename; do
  ln -sf "$(command -v "$tool")" "$empty_stub/$tool"
done

run_doctor() {
  local bin_dir="$1"
  shift
  # Only the stub bin and the repo bin: PATH must not fall through to the
  # host, or a missing-required-command check would find the real binary.
  OMARCHY_PATH="$fake_root" OMARCHY_OS_RELEASE="${OMARCHY_OS_RELEASE:-/etc/os-release}" \
    PATH="$bin_dir:$ROOT/bin" "$doctor" "$@"
}

# --- text mode -----------------------------------------------------------

set +e
output=$(run_doctor "$stub_bin")
status=$?
set -e
(( status == 1 )) || fail "doctor exits non-zero when a required check fails"
[[ $output == *"CHECK"* ]] || fail "text mode prints a header"
[[ $output == *"STATE"* ]] || fail "text mode prints column headers"
[[ $output == *"DETAIL"* ]] || fail "text mode prints column headers"
[[ $output == *"os"* ]] || fail "text mode reports the OS check"
[[ $output == *"omarchy-path"* ]] || fail "text mode reports the path check"
pass "doctor text mode renders and fails on a missing install"

# --- JSON mode -----------------------------------------------------------

set +e
json=$(run_doctor "$stub_bin" --json)
status=$?
set -e
(( status == 1 )) || fail "doctor --json exits non-zero when a required check fails"
echo "$json" | jq -e '.omarchy_path == "'"$fake_root"'"' >/dev/null ||
  fail "JSON reports the configured OMARCHY_PATH"
echo "$json" | jq -e '.checks | type == "array"' >/dev/null ||
  fail "JSON wraps checks in an array"
echo "$json" | jq -e 'any(.checks[]; .name == "os")' >/dev/null ||
  fail "JSON includes the os check"
pass "doctor --json emits machine-readable health"

# --- missing optional hardware does not fail the run ----------------------

# An empty Omarchy tree is missing every optional command and every hardware
# probe, so all of those must be warnings rather than failures.
echo "$json" | jq -e 'any(.checks[]; .name == "command:hyprctl" and .status == "warn")' >/dev/null ||
  fail "missing optional hyprctl is a warning"
echo "$json" | jq -e 'any(.checks[]; .name == "command:waybar" and .status == "warn")' >/dev/null ||
  fail "missing optional waybar is a warning"
echo "$json" | jq -e 'any(.checks[]; .name == "battery" and .status == "warn")' >/dev/null ||
  fail "missing battery is a warning"
pass "missing optional hardware reports warnings without failing"

# --- missing required command is a hard failure --------------------------

set +e
bare_json=$(run_doctor "$empty_stub" --json)
bare_status=$?
set -e
(( bare_status == 1 )) || fail "doctor fails when a required command is missing"
echo "$bare_json" | jq -e 'any(.checks[]; .name == "command:pacman" and .status == "fail")' >/dev/null ||
  fail "JSON reports a missing required command as a failure"
echo "$bare_json" | jq -e 'any(.checks[]; .name == "command:git" and .status == "fail")' >/dev/null ||
  fail "JSON reports a missing required git as a failure"
pass "missing required command is a hard failure"

# --- non-Arch host --------------------------------------------------------

# /etc/os-release is read-only, so the host's own file drives this check. The
# sandbox is not Arch, which is exactly the failure we want to observe.
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *arch* ]]; then
    skip "host is Arch-based; the non-Arch branch cannot be exercised here"
    exit 0
  fi
fi

set +e
output=$(run_doctor "$stub_bin" 2>&1)
status=$?
set -e
(( status == 1 )) || fail "doctor fails on a non-Arch host"
[[ $output == *"Omarchy requires an Arch-based system"* ]] ||
  fail "doctor explains the non-Arch failure"
pass "doctor detects a non-Arch host"

# --- a healthy tree passes ------------------------------------------------

# The tree must also be a git repository, or the git-state check reports a
# warning and the run fails. Initialize a throwaway repo so the check is real
# without touching the real one.
git init -q "$fake_root"

# The host here is not Arch, so the os check would fail. Provide a stub
# os-release so the healthy-tree path can be exercised in isolation.
os_release="$tmp_dir/os-release"
printf 'NAME="Arch Linux"\nID=arch\nPRETTY_NAME="Arch Linux"\n' >"$os_release"
mkdir -p "$fake_root/migrations" "$fake_root/bin"
set +e
output=$(OMARCHY_OS_RELEASE="$os_release" run_doctor "$stub_bin")
status=$?
set -e
(( status == 0 )) || fail "doctor passes when every required check succeeds"
[[ $output == *"migrations"* ]] || fail "doctor reports the migrations directory"
[[ $output == *"commands"* ]] || fail "doctor reports the command directory"
pass "doctor passes on a healthy tree"

# --- read-only guarantee --------------------------------------------------

# The command must not create the directories it inspects. Run it against a
# path that does not exist yet and confirm it stays absent.
missing_root="$tmp_dir/does-not-exist"
set +e
OMARCHY_PATH="$missing_root" PATH="$stub_bin:$ROOT/bin" "$doctor" >/dev/null 2>&1
status=$?
set -e
(( status == 1 )) || fail "doctor fails when OMARCHY_PATH is absent"
[[ ! -e $missing_root ]] || fail "doctor created the missing OMARCHY_PATH"
pass "doctor does not create directories as a side effect"