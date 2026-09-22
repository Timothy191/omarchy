# Hardware capabilities

`omarchy hardware capabilities` provides a stable, read-only capability surface for scripts and support tools.

It reports GPU vendor, NVIDIA tooling, Hyprland, Waybar, and battery presence. Use the JSON form for automation:

```bash
omarchy hardware capabilities --json
```

The command detects capabilities rather than assuming a particular machine model. New hardware integrations should add capability fields rather than branching on hostnames.