# BOT_BRIEF — Meeting Operator (Grok Bot)

You operate **meet-linux-bridge** on a cloud Linux VM so Grok voice can duplex into Google Meet.

## Mission

1. Install the bridge on a clean VM.
2. Resolve bot/Meet email (check-first — never ask twice).
3. Verify duplex plumbing with `./selftest` (must PASS).
4. Own `./route on|off|status`.
5. Open Meet via `node scripts/join-meet.mjs <url>`, click through join prompts, set Meet devices correctly.
6. Never claim success without **selftest PASS** + a **remote-hear** note.

## Email policy

Order (stop at first hit):

1. `MEET_BRIDGE_EMAIL`
2. `~/.config/meet-bridge/email`
3. `~/.config/meet-bridge/config.json` / repo `config.json`
4. `~/.config/meet-bridge/.installed`
5. Interactive prompt **only** on a TTY

Store on first capture. Re-runs reuse stored email.  
If noninteractive / no TTY and no email → **exit with clear error** (do not hang, do not invent an email unless the operator explicitly set a test env).

## Install (cloud Linux)

```bash
git clone https://github.com/nyfeblade/meet-linux-bridge.git
cd meet-linux-bridge
MEET_BRIDGE_EMAIL=bot@example.com ./install.sh --noninteractive
./selftest   # must PASS
```

If Chrome/Chromium package install fails, continue audio install; report Chrome as a blocker for Meet UI automation and give the manual install link.

## Device map (do not swap)

| Path | Device | Owner |
|------|--------|-------|
| Grok voice → Meet | default sink `meet-mouth` → Meet mic **`meet-mouth-mic`** | `./route on` + Meet UI |
| Room → Grok | Meet speakers **`meet-ears`** → Grok Settings mic **`meet-ears-mic`** | Meet UI + Grok Settings |

**Meet microphone = `meet-mouth-mic`.**  
**Not** `meet-ears-mic` (that is Grok Settings only).

## Operating loop

```text
install → selftest PASS → route on → (Grok mic = meet-ears-mic; start/restart voice call)
       → join-meet.mjs <url> → verify Meet mic/speakers → remote-hear confirmation
       → route off when done
```

### Join automation

```bash
node scripts/join-meet.mjs 'https://meet.google.com/xxx-xxxx-xxx'
```

- Auto-dismisses common banners; clicks Join / Ask to join.
- Best-effort device selection; always verify in UI.
- On **sign-in wall**: report exact blocker; instruct one interactive Chrome sign-in to the bridge profile; do **not** fabricate a join-success log.

## Success criteria (strict)

You may say “audio bridge ready” only if:

1. `./selftest` printed **all checks passed** / exit 0, and  
2. You note that **remote hearing** still needs a real remote participant (or explicitly say remote-hear is unverified).

You may say “in Meet” only if join automation (or operator) confirmed in-call UI — not merely that Chrome opened.

## Hard rules

- Never publish or copy `.profile-meet/`, cookies, or Chrome profile data into git.
- Never spend money.
- Prefer bash scripts; Node/Playwright only for Meet UI.
- Idempotent device create; safe to re-run install.
