# How Grok brain + voice get into Meet on Fedora (locked)

## What works (selftest PASS)
- Mouth loop: play into `meet-mouth` → readable on `meet-mouth-mic` (Meet mic path)
- Ears loop: play into `meet-ears` → readable on `meet-ears-mic` (Grok mic path)
- No echo between mouth and ears
- Bot-only box: **no Multi-out**; while routed, default sink = `meet-mouth` (Grok voice goes straight to the Meet mic path)

## Device map (Mac ↔ Linux)

| Role | Mac (BlackHole) | Fedora (PipeWire) |
|------|-----------------|-------------------|
| Mouth sink (Grok default out) | Meet Mouth Multi → BH 2ch (or BH 2ch alone) | `meet-mouth` |
| Meet microphone | BlackHole 2ch | `meet-mouth-mic` (or `meet-mouth.monitor`) |
| Meet speakers / ears sink | BlackHole 16ch (output) | `meet-ears` |
| Grok Settings mic | BlackHole 16ch (input) | `meet-ears-mic` (or `meet-ears.monitor`) |

## Architecture

| Role | Mechanism |
|------|-----------|
| Brain + Grok voice | Grok Bot voice call |
| Mouth into Meet | `./route on` → default sink = `meet-mouth`; Meet mic = `meet-mouth-mic` |
| Ears (room → Grok) | Meet speakers = `meet-ears` → Grok Settings mic = `meet-ears-mic` |

## Commands

```bash
cd /path/to/meet-linux-bridge
./devices.sh create     # or just ./route on (creates if needed)
./selftest              # plumbing only — expect all PASS
./route on              # Grok default output → meet-mouth
./route status
./route off             # restore previous default sink
./devices.sh destroy    # teardown virtual devices
```

## Manual dogfood checklist (Luke)

1. Chrome: use a **dedicated Meet identity** profile (real Chrome, not Playwright). Tip:
   `google-chrome --user-data-dir="$HOME/.config/meet-bridge/chrome-profile"`
2. `./route on`
3. Grok Bot → Settings → Microphone = **`meet-ears-mic`**
4. Start Grok Bot voice call (hang up & restart if it was already open before route on)
5. Join Meet in that Chrome profile; set:
   - Microphone = **`meet-mouth-mic`** (unmuted)
   - Speakers = **`meet-ears`**
6. Proof bar: a **remote** participant hears Grok (same-machine dogfood alone is not enough)
7. Done: hang up Grok; set Grok mic back to real mic; `./route off`; optionally `./devices.sh destroy`

## Teardown

```bash
./route off
./devices.sh destroy
```

Devices are session-local PipeWire null sinks + remap sources (module IDs in `runtime/modules.env`). They vanish on logout/reboot if not recreated.

## Notes
- Stack: PipeWire 1.6.8 + pipewire-pulse (`pactl` modules)
- Grok Bot: `grok-bot-0.61.0` (`/usr/bin/grok-bot`) — no speaker picker; voice follows system default sink
- EasyEffects / AirPlay sinks on this machine are unrelated; leave them alone
