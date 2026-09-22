# Persistent state

Omarchy persistent state is intended to describe user-visible toggles and workflow markers, not executable configuration.

Use `omarchy state export` to inspect state without changing it:

```bash
omarchy state export
```

State consumers should treat unknown keys as opaque and avoid depending on incidental filesystem ordering. New state should be introduced with a documented name and migration path.

This keeps configuration, mutable state, and package-owned files separable so updates can preserve user intent without treating the entire home directory as an opaque backup.
