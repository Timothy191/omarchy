# Platform hardening

The platform-hardening command set is deliberately read-only except for the migration runner itself.

## Diagnostics

- `omarchy doctor` checks the Arch base, Omarchy paths, required commands, systemd state, package presence, GPU presence, battery presence, Git cleanliness, and snapshot tooling.
- `omarchy doctor --json` emits machine-readable results.
- Optional hardware and snapshot capabilities are warnings/informational states rather than failures.

## Update preflight

`omarchy update preflight` reuses the existing free-space and update-lock commands instead of duplicating their implementation. It checks:

- free space required by the update pipeline
- pacman transaction lock
- Omarchy update lock
- systemd state
- pending migrations
- snapshot tooling
- root filesystem accessibility

Only hard prerequisites block the command. Pending migrations and degraded systemd are reported as warnings.

## Migrations

`omarchy-migrate` remains the single migration engine. Completion markers are written only after the migration exits successfully. Marker creation uses a temporary file followed by an atomic rename, and a migration lock prevents concurrent runners.

A failed migration therefore remains pending and can be retried.

## Hardware capabilities

`omarchy hardware capabilities --json` exposes boolean capabilities rather than machine-model assumptions:

- `gpu`
- `gpu_nvidia`
- `gpu_amd`
- `gpu_intel`
- `nvidia_smi`
- `hyprland`
- `waybar`
- `battery`

Unknown or absent hardware is represented as false rather than as a special machine type.

## Persistent state

`omarchy state export` reports the names of regular files directly under the Omarchy state directory. It does not read, execute, modify, or recursively copy state contents. Filenames are JSON-escaped, including unusual characters.

All hardening commands are intended to be safe to run during diagnosis; they do not install packages, restart services, create snapshots, or modify configuration.
