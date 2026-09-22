#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="$ROOT/bin/omarchy-doctor"
PREFLIGHT="$ROOT/bin/omarchy-update-preflight"
CAPS="$ROOT/bin/omarchy-hardware-capabilities"
[[ -x "$DOCTOR" && -x "$PREFLIGHT" && -x "$CAPS" ]]
bash -n "$DOCTOR"
bash -n "$PREFLIGHT"
bash -n "$CAPS"
doctor_json=$(OMARCHY_PATH="$ROOT" "$DOCTOR" --json || true)
grep -q '"checks":' <<<"$doctor_json"
preflight_json=$("$PREFLIGHT" --json || true)
grep -q '"checks":' <<<"$preflight_json"
caps_json=$("$CAPS" --json)
grep -q '"gpu_vendor":' <<<"$caps_json"
echo "platform hardening smoke tests passed"
