#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command flock

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAKEBIN="$TMP/bin"
mkdir -p "$FAKEBIN"

cat >"$FAKEBIN/pacman" <<'SH'
#!/bin/bash
[[ $1 == -Q && $2 == omarchy ]] && exit 0
exit 0
SH
cat >"$FAKEBIN/systemctl" <<'SH'
#!/bin/bash
[[ $1 == is-system-running ]] && { echo running; exit 0; }
exit 0
SH
cat >"$FAKEBIN/git" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$FAKEBIN/lspci" <<'SH'
#!/bin/bash
echo '01:00.0 VGA compatible controller: NVIDIA Corporation Test GPU'
SH
cat >"$FAKEBIN/nvidia-smi" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$FAKEBIN/hyprctl" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$FAKEBIN/waybar" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$FAKEBIN/snapper" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$FAKEBIN"/*

FAKE_OMARCHY="$TMP/omarchy"
mkdir -p "$FAKE_OMARCHY/bin" "$FAKE_OMARCHY/migrations" "$TMP/power/BAT0"
cat >"$TMP/os-release" <<'EOF_OS'
ID=arch
ID_LIKE=arch
PRETTY_NAME="Test Arch"
EOF_OS

PATH="$FAKEBIN:$ROOT/bin:$PATH" OMARCHY_PATH="$FAKE_OMARCHY" OMARCHY_OS_RELEASE_PATH="$TMP/os-release" OMARCHY_POWER_SUPPLY_PATH="$TMP/power"   "$ROOT/bin/omarchy-doctor" --json >"$TMP/doctor.json"

jq -e '.checks | any(.[]; .name == "os" and .status == "ok")' "$TMP/doctor.json" >/dev/null
jq -e '.checks | any(.[]; .name == "battery" and .status == "ok")' "$TMP/doctor.json" >/dev/null
jq -e '.checks | any(.[]; .name == "gpu" and .status == "ok")' "$TMP/doctor.json" >/dev/null
pass "doctor returns valid JSON with required and optional checks"

if PATH="$FAKEBIN:$ROOT/bin:$PATH" OMARCHY_PATH="$FAKE_OMARCHY" OMARCHY_OS_RELEASE_PATH="$TMP/missing-os" "$ROOT/bin/omarchy-doctor" >/dev/null 2>&1; then
  fail "doctor fails when os-release is unavailable"
fi
pass "doctor fails safely when os-release is unavailable"

cat >"$FAKEBIN/omarchy-update-requires-free-space" <<'SH'
#!/bin/bash
exit "${FAKE_SPACE_RC:-0}"
SH
cat >"$FAKEBIN/omarchy-update-lock" <<'SH'
#!/bin/bash
[[ ${FAKE_UPDATE_HELD:-0} == 1 ]] && exit 0
exit 1
SH
cat >"$FAKEBIN/omarchy-migrate" <<'SH'
#!/bin/bash
exit "${FAKE_MIGRATE_RC:-1}"
SH
cat >"$FAKEBIN/omarchy-snapshot" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$FAKEBIN"/omarchy-update-* "$FAKEBIN"/omarchy-migrate "$FAKEBIN"/omarchy-snapshot

FAKE_SPACE_RC=0 FAKE_UPDATE_HELD=0 FAKE_MIGRATE_RC=1 PATH="$FAKEBIN:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-update-preflight" --json >"$TMP/preflight.json"

jq -e '.checks | any(.[]; .name == "disk-space" and .status == "ok")' "$TMP/preflight.json" >/dev/null
jq -e '.checks | any(.[]; .name == "migrations" and .status == "ok")' "$TMP/preflight.json" >/dev/null
pass "preflight reuses update checks and interprets no pending migrations correctly"

if FAKE_SPACE_RC=1 PATH="$FAKEBIN:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-update-preflight" >/dev/null 2>&1; then
  fail "preflight blocks insufficient disk space"
fi
pass "preflight blocks insufficient disk space"

if FAKE_UPDATE_HELD=1 PATH="$FAKEBIN:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-update-preflight" >/dev/null 2>&1; then
  fail "preflight blocks an active update lock"
fi
pass "preflight blocks an active update lock"

MIGRATIONS="$TMP/migrations"
STATE="$TMP/state"
RUNTIME="$TMP/runtime"
mkdir -p "$MIGRATIONS" "$STATE" "$RUNTIME"

cat >"$MIGRATIONS/001-success.sh" <<SH
#!/bin/bash
echo success >>"$TMP/migration.log"
SH
chmod +x "$MIGRATIONS/001-success.sh"

PATH="$FAKEBIN:$ROOT/bin:$PATH" OMARCHY_PATH="$TMP" OMARCHY_MIGRATION_STATE="$STATE" XDG_RUNTIME_DIR="$RUNTIME"   "$ROOT/bin/omarchy-migrate"

[[ -f "$STATE/001-success.sh" ]] || fail "successful migration writes completion marker"
pass "successful migration writes completion marker after execution"

cat >"$MIGRATIONS/002-fail.sh" <<'SH'
#!/bin/bash
exit 7
SH
chmod +x "$MIGRATIONS/002-fail.sh"

if PATH="$FAKEBIN:$ROOT/bin:$PATH" OMARCHY_PATH="$TMP" OMARCHY_MIGRATION_STATE="$STATE" XDG_RUNTIME_DIR="$RUNTIME" "$ROOT/bin/omarchy-migrate" >/dev/null 2>&1; then
  fail "failed migration returns failure"
fi
[[ ! -e "$STATE/002-fail.sh" ]] || fail "failed migration does not write completion marker"
pass "failed migration remains retryable"

HWJSON=$(PATH="$FAKEBIN:$ROOT/bin:$PATH" OMARCHY_POWER_SUPPLY_PATH="$TMP/power" "$ROOT/bin/omarchy-hardware-capabilities" --json)
jq -e '.gpu == true and .gpu_nvidia == true and .nvidia_smi == true and .hyprland == true and .waybar == true and .battery == true' <<<"$HWJSON" >/dev/null
pass "hardware capability JSON exposes capabilities as booleans"

STATE_EXPORT="$TMP/state-export"
mkdir -p "$STATE_EXPORT"
printf x >"$STATE_EXPORT/normal"
printf x >"$STATE_EXPORT/'\"unsafe\""
python3 - "$STATE_EXPORT" <<'PY'
import pathlib
import sys
(pathlib.Path(sys.argv[1]) / 'line\nfeed').write_text('x')
PY

EXPORTED=$(HOME="$TMP" XDG_STATE_HOME="$TMP" "$ROOT/bin/omarchy-state-export")
jq -e '.entries | length == 3' <<<"$EXPORTED" >/dev/null
jq -e '.entries | index("normal") != null and index("line\nfeed") != null' <<<"$EXPORTED" >/dev/null
pass "state export safely serializes multiple and unusual filenames"

for script in   "$ROOT/bin/omarchy-doctor"   "$ROOT/bin/omarchy-update-preflight"   "$ROOT/bin/omarchy-migrate"   "$ROOT/bin/omarchy-hardware-capabilities"   "$ROOT/bin/omarchy-state-export"; do
  bash -n "$script"
done
pass "platform-hardening scripts pass bash syntax validation"
