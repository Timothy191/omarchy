# Update Preflight

`omarchy update preflight` performs read-only checks before an update.

It checks available root filesystem space, pacman transaction state, the Omarchy update lock, systemd health, and whether migrations are pending. It does not acquire locks, install packages, create snapshots, or modify configuration.

Use:

```bash
omarchy update preflight
omarchy update preflight --json
```

A failed prerequisite exits with status 1. A pending migration is reported as a warning because the update itself owns the migration sequence.

The disk-space check reuses `omarchy-update-requires-free-space` so the preflight threshold and the update's own threshold always agree.