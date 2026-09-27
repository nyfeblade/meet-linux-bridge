# Meeting Operator setup (detailed)

> **Bot template link (also at top of root README):**  
> **Bot template (clone / install):** [Meeting Operator](grokbot://app/v1/bot-template?id=M9Kc9ZH7lrhbTvP2Bc6TM) · https://x.ai/bot/M9Kc9ZH7lrhbTvP2Bc6TM  
> Repo install:
> ```bash
> git clone https://github.com/nyfeblade/meet-linux-bridge.git
> cd meet-linux-bridge
> MEET_BRIDGE_EMAIL=you@example.com ./install.sh --noninteractive
> ```

## What this is

Linux PipeWire/Pulse bridge + Chrome Meet join helper so **Grok Bot voice** duplexes into **Google Meet**.

## Device map (do not swap)

| Path | Device | Set by |
|------|--------|--------|
| Grok voice → Meet | default sink `meet-mouth` → Meet mic **`meet-mouth-mic`** | `./route on` + Meet UI |
| Room → Grok | Meet speakers **`meet-ears`** → Grok mic **`meet-ears-mic`** | Meet UI + Grok Settings |

**Meet microphone = `meet-mouth-mic`.** Never `meet-ears-mic` in Meet.

## Email policy

Check-first, never ask twice:

1. `MEET_BRIDGE_EMAIL`  
2. `~/.config/meet-bridge/email`  
3. `config.json` (config dir or repo)  
4. `~/.config/meet-bridge/.installed`  
5. TTY prompt only  

No TTY + no email → clear exit error (no hang).

## Install on clean cloud Linux VM

```bash
git clone https://github.com/nyfeblade/meet-linux-bridge.git
cd meet-linux-bridge
MEET_BRIDGE_EMAIL=bot@example.com ./install.sh --noninteractive
./selftest   # must PASS before claiming plumbing works
```

Chrome/Chromium may need a manual install on some distros — continue audio setup and report that blocker for Meet UI automation.

## Human clicks / what working sounds like

1. Install (above).  
2. One-time Chrome sign-in:  
   `google-chrome --user-data-dir="$HOME/.config/meet-bridge/chrome-profile"`  
3. `./route on`  
4. Grok Bot → Settings → Microphone = **`meet-ears-mic`**  
5. Start or **restart** Grok voice call after route on.  
6. Join Meet (`node scripts/join-meet.mjs <url>` or manually). In Meet:  
   - Microphone = **`meet-mouth-mic`** (unmuted)  
   - Speakers = **`meet-ears`**  
7. **Working:** remote hears Grok; Grok hears room. Same-machine dogfood alone is not enough.

## Bot operating loop

```text
install → selftest PASS → route on → Grok mic=meet-ears-mic → voice call
       → join-meet.mjs <url> → verify Meet devices → remote-hear note
       → route off when done
```

### Join automation

```bash
node scripts/join-meet.mjs 'https://meet.google.com/xxx-xxxx-xxx'
```

- Auto-allows mic/cam prompts; clicks Join / Ask to join.  
- Best-effort device selection — verify in UI.  
- Sign-in wall → report exact blocker; one interactive sign-in; **do not invent success**.

Env: `MEET_URL`, `MEET_HEADLESS=1`, `MEET_CLOSE=1`, `CHROME_PATH`, `MEET_BRIDGE_EMAIL`.

## Success criteria (strict)

- “Audio bridge ready” only after `./selftest` exit 0 **and** you note remote-hear status (verified or unverified).  
- “In Meet” only when in-call UI is confirmed — not merely Chrome opened.

## Teardown

```bash
./route off
./devices.sh destroy
```

## Hard rules

- Never push Chrome profiles / `.profile-meet` / cookies.  
- Never spend money.  
- Prefer bash; Playwright only for Meet UI.  
- See also [`BOT_BRIEF.md`](../BOT_BRIEF.md) and [`WORKS.md`](../WORKS.md).
