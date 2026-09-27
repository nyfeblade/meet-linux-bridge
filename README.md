# meet-linux-bridge

> **Bot template (clone / install):** [Meeting Operator](grokbot://app/v1/bot-template?id=M9Kc9ZH7lrhbTvP2Bc6TM) · https://x.ai/bot/M9Kc9ZH7lrhbTvP2Bc6TM  
> Git clone install: `git clone https://github.com/nyfeblade/meet-linux-bridge.git && cd meet-linux-bridge && MEET_BRIDGE_EMAIL=you@example.com ./install.sh --noninteractive`  
> Detailed Meeting Operator walkthrough → [`docs/bot-setup.md`](docs/bot-setup.md)

PipeWire/Pulse **audio bridge** so a Grok Bot voice call can talk and listen inside **Google Meet** on Linux (Fedora/RHEL or Debian/Ubuntu).

Virtual devices:

| Role | Device | Who selects it |
|------|--------|----------------|
| Mouth sink (Grok default output) | `meet-mouth` | `./route on` sets system default sink |
| Meet microphone | **`meet-mouth-mic`** | Chrome Meet UI |
| Meet speakers | **`meet-ears`** | Chrome Meet UI |
| Grok Bot microphone | **`meet-ears-mic`** | Grok Bot → Settings → Microphone |

> **Do not** set Meet’s mic to `meet-ears-mic`. That input is for Grok Settings only.

## One-command install (clean cloud Linux VM)

```bash
git clone https://github.com/nyfeblade/meet-linux-bridge.git
cd meet-linux-bridge
MEET_BRIDGE_EMAIL=you@example.com ./install.sh --noninteractive
```

Or interactive (prompts **once** for email if nothing is stored):

```bash
./install.sh
```

### Email policy (check-first, never ask twice)

1. `MEET_BRIDGE_EMAIL` env  
2. `~/.config/meet-bridge/email`  
3. `~/.config/meet-bridge/config.json` (or local `config.json`)  
4. `~/.config/meet-bridge/.installed` marker  
5. Interactive prompt **only** if stdin is a TTY  

Stored on first capture. Noninteractive / no-TTY **exits with a clear error** if no email is found (never hangs).

`install.sh` also installs pipewire/pulse utils + ffmpeg, creates an empty Chrome user-data-dir, creates virtual devices (idempotent), and runs `./selftest` (must PASS).

## Day-to-day commands

```bash
./selftest              # plumbing only — expect all PASS
./route on              # default sink → meet-mouth
./route status
./route off
node scripts/join-meet.mjs 'https://meet.google.com/xxx-xxxx-xxx'
```

## Short walkthrough

1. Install with your Meet/bot Google email.  
2. Sign in Chrome once to `~/.config/meet-bridge/chrome-profile`.  
3. `./route on` → Grok Settings mic = **`meet-ears-mic`** → start/restart Grok voice call.  
4. Join Meet; set mic = **`meet-mouth-mic`**, speakers = **`meet-ears`**.  
5. Proof: a **remote** participant hears Grok.  

Full operator checklist, automation notes, and success rules: **[`docs/bot-setup.md`](docs/bot-setup.md)** · architecture lock: [`WORKS.md`](WORKS.md) · bot brief: [`BOT_BRIEF.md`](BOT_BRIEF.md)

## Safety

Never commit `.profile-meet/`, Chrome profiles, or runtime secrets. Config lives in `~/.config/meet-bridge/`. No spending.
