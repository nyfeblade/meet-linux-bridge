# meet-linux-bridge

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

Resolution order:

1. `MEET_BRIDGE_EMAIL` env
2. `~/.config/meet-bridge/email`
3. `~/.config/meet-bridge/config.json` (or local `config.json`)
4. `~/.config/meet-bridge/.installed` marker
5. Interactive prompt **only** if stdin is a TTY

On first capture the email is stored under `~/.config/meet-bridge/`. Re-runs reuse it.  
Noninteractive / no-TTY **exits with a clear error** if no email is found (never hangs).

`install.sh` also:

- Installs `pipewire` / `pulseaudio-utils` / `ffmpeg` / `python3` (and tries Chrome/Chromium)
- Creates empty Chrome user-data-dir: `~/.config/meet-bridge/chrome-profile`
- Creates virtual devices (idempotent)
- Runs `./selftest` (must PASS)

## Day-to-day commands

```bash
./devices.sh create     # usually unnecessary after install / route on
./selftest              # plumbing only — expect all PASS
./route on              # default sink → meet-mouth
./route status
./route off             # restore previous default sink
./devices.sh destroy    # teardown virtual devices
```

Join Meet (Playwright + system Chrome when available):

```bash
# Sign in once to the bridge profile (human):
google-chrome --user-data-dir="$HOME/.config/meet-bridge/chrome-profile"

# Then:
./route on
node scripts/join-meet.mjs 'https://meet.google.com/xxx-xxxx-xxx'
```

## Short walkthrough (what working sounds like)

### Human clicks / settings

1. **Install** with your Meet/bot Google email (see above).
2. **Sign in Chrome once** to `~/.config/meet-bridge/chrome-profile` as that email.
3. Run **`./route on`**.
4. In **Grok Bot → Settings → Microphone**, choose **`meet-ears-mic`**.
5. Start (or restart) the **Grok Bot voice call** *after* route on.
6. Join Meet (script or manually). In Meet UI set:
   - **Microphone = `meet-mouth-mic`** (unmuted)
   - **Speakers = `meet-ears`**
7. Proof: a **remote** participant hears Grok; you (or the bot) hear the room via Grok. Same-machine loopback alone is not enough.

### What the bot owns

- `./install.sh` / `./setup.sh`
- `./route on|off|status`
- `./selftest` (must PASS before claiming audio plumbing works)
- `node scripts/join-meet.mjs <url>` (join prompts, best-effort device picks)
- Never claims full success without **selftest PASS** + **remote-hear** note

### What working sounds like

- Grok speaks → remote Meet participant hears it (mouth path).
- Remote speaks → Grok hears them (ears path).
- No echo of Grok’s own voice back into Grok (`./selftest` “no echo” check).

## Dogfood checklist

- [ ] `./selftest` → all PASS  
- [ ] `./route on`  
- [ ] Grok mic = `meet-ears-mic`  
- [ ] Voice call started/restarted after route on  
- [ ] Meet mic = `meet-mouth-mic`, speakers = `meet-ears`  
- [ ] Remote participant confirms hearing Grok  
- [ ] Done: hang up Grok; restore Grok mic; `./route off`

## Meet automation notes

`scripts/join-meet.mjs` uses Playwright with a **persistent** Chrome user-data-dir (no secrets in the repo). It:

- Auto-allows mic/cam permission prompts (`--use-fake-ui-for-media-stream`)
- Clicks Join / Ask to join when visible
- Best-effort selects `meet-mouth-mic` / `meet-ears`
- If a **Google sign-in wall** appears, exits with blocker details (does not invent a success log)

Optional env: `MEET_URL`, `MEET_HEADLESS=1`, `MEET_CLOSE=1`, `CHROME_PATH`.

## Layout

```
install.sh      # one-command install
setup.sh        # email + chrome profile only
lib.sh          # shared Pulse helpers
devices.sh      # create|destroy|status
route           # on|off|status
selftest        # duplex plumbing tests
scripts/join-meet.mjs
WORKS.md        # locked architecture notes
BOT_BRIEF.md    # Grok Bot Meeting Operator brief
```

## Safety

- **Never** commit `.profile-meet/`, Chrome profiles, or runtime secrets.
- Config lives in `~/.config/meet-bridge/` (gitignored locally).
- No paid APIs; no spending.

## License

MIT (or as declared by the repository owner).
