#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

caps="$ROOT/bin/omarchy-hardware-capabilities"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Each argument is a PCI device as "vendor:device:class", in sysfs's own format.
write_pci_devices() {
  rm -rf "$tmp_dir/devices"
  mkdir -p "$tmp_dir/devices"

  local index=0
  local spec
  for spec in "$@"; do
    local slot
    slot=$(printf '0000:%02x:00.0' "$index")
    mkdir -p "$tmp_dir/devices/$slot"
    printf '%s\n' "${spec%%:*}" >"$tmp_dir/devices/$slot/vendor"
    printf '%s\n' "$(cut -d: -f2 <<<"$spec")" >"$tmp_dir/devices/$slot/device"
    printf '%s\n' "${spec##*:}" >"$tmp_dir/devices/$slot/class"
    index=$((index + 1))
  done
}

run_caps() {
  OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" PATH="$ROOT/bin:$PATH" "$caps" "$@"
}

# --- GPU vendor detection -------------------------------------------------

write_pci_devices 0x1002:0x15e7:0x030000
output=$(run_caps)
[[ $output == *"gpu_vendor=amd"* ]] || fail "AMD GPU is detected as amd"
pass "AMD GPU vendor is detected"

write_pci_devices 0x10de:0x2560:0x030200
output=$(run_caps)
[[ $output == *"gpu_vendor=nvidia"* ]] || fail "NVIDIA GPU is detected as nvidia"
pass "NVIDIA GPU vendor is detected"

write_pci_devices 0x8086:0x9a21:0x030000
output=$(run_caps)
[[ $output == *"gpu_vendor=intel"* ]] || fail "Intel GPU is detected as intel"
pass "Intel GPU vendor is detected"

# A non-display NVIDIA function (audio) must not be reported as a GPU vendor.
write_pci_devices 0x10de:0x228e:0x040300
output=$(run_caps)
[[ $output == *"gpu_vendor=none"* ]] || fail "a non-display NVIDIA function is not a GPU"
pass "a non-display NVIDIA function is not reported as a GPU"

write_pci_devices
output=$(run_caps)
[[ $output == *"gpu_vendor=none"* ]] || fail "no PCI devices reports no GPU vendor"
pass "no PCI devices reports no GPU vendor"

# --- capability booleans --------------------------------------------------

set +e
json=$(run_caps --json)
status=$?
set -e
(( status == 0 )) || fail "capabilities exits zero"
echo "$json" | jq -e '.gpu_vendor == "none"' >/dev/null ||
  fail "JSON reports the GPU vendor"
echo "$json" | jq -e '.nvidia_smi == 0' >/dev/null ||
  fail "JSON reports nvidia_smi as a boolean"
echo "$json" | jq -e '.hyprland == 0' >/dev/null ||
  fail "JSON reports hyprland as a boolean"
echo "$json" | jq -e '.waybar == 0' >/dev/null ||
  fail "JSON reports waybar as a boolean"
echo "$json" | jq -e '.battery == 0' >/dev/null ||
  fail "JSON reports battery as a boolean"
pass "capabilities --json emits machine-readable booleans"

# --- missing optional software reports false ------------------------------

# The sandbox has no Hyprland, Waybar, or nvidia-smi, so the booleans above
# are the expected false values. Confirm that explicitly rather than assuming.
echo "$json" | jq -e '.hyprland == 0 and .waybar == 0 and .nvidia_smi == 0' >/dev/null ||
  fail "missing optional software reports false"
pass "missing optional software reports false"

# --- no battery is not an error ------------------------------------------

# A desktop with no battery must still exit zero.
set +e
run_caps >/dev/null
status=$?
set -e
(( status == 0 )) || fail "capabilities exits zero on a desktop without a battery"
pass "capabilities exits zero without a battery"