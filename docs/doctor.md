# Omarchy Doctor

`omarchy doctor` is a read-only health check for an Omarchy installation.

## Goals

- Detect unsupported or unexpected host state before troubleshooting.
- Surface missing required commands and Omarchy directories.
- Report systemd health, repository state, package state, GPU detection, and battery presence.
- Provide machine-readable output for support tooling.

## Usage

```bash
omarchy doctor
omarchy doctor --json
```

The command does not install packages, change configuration, restart services, modify migrations, or repair the machine.

A non-zero exit status means at least one required health check failed.
