# Omarchy Doctor

`omarchy doctor` is a read-only health check for an installed Omarchy system.

## Usage

```bash
omarchy doctor
omarchy doctor --json
```

The command checks the Arch-based operating system, Omarchy installation path, core commands, migrations and command directories, systemd availability, local git state, package state, GPU detection, and battery presence.

It does not install packages, edit configuration, restart services, create snapshots, or change persistent state.

A failing required check exits with status 1. Optional hardware checks may report warnings without failing the command. JSON output is intended for support tooling and automation.

## Design rule

Doctor should remain safe to run while diagnosing a failed update or migration. It must not mutate the system as a side effect of inspection.
