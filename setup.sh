#!/usr/bin/env bash
# Resolve Meet/bot email (check-first, never ask twice) and prepare Chrome profile dir.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${MEET_BRIDGE_CONFIG_DIR:-$HOME/.config/meet-bridge}"
CHROME_PROFILE_DIR="${MEET_BRIDGE_CHROME_DIR:-$HOME/.config/meet-bridge/chrome-profile}"

mkdir -p "$CONFIG_DIR" "$CHROME_PROFILE_DIR" "$DIR/runtime"

resolve_email() {
  local email=""
  if [[ -n "${MEET_BRIDGE_EMAIL:-}" ]]; then
    email="$(echo "$MEET_BRIDGE_EMAIL" | tr -d '[:space:]')"
    echo "[setup] email from MEET_BRIDGE_EMAIL" >&2
  fi
  if [[ -z "$email" && -f "$CONFIG_DIR/email" ]]; then
    email="$(tr -d '[:space:]' < "$CONFIG_DIR/email")"
    [[ -n "$email" ]] && echo "[setup] email from $CONFIG_DIR/email" >&2
  fi
  if [[ -z "$email" && -f "$CONFIG_DIR/config.json" ]]; then
    email="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("email","") or "")' "$CONFIG_DIR/config.json" 2>/dev/null || true)"
    email="$(echo "$email" | tr -d '[:space:]')"
    [[ -n "$email" ]] && echo "[setup] email from $CONFIG_DIR/config.json" >&2
  fi
  if [[ -z "$email" && -f "$DIR/config.json" ]]; then
    email="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("email","") or "")' "$DIR/config.json" 2>/dev/null || true)"
    email="$(echo "$email" | tr -d '[:space:]')"
    [[ -n "$email" ]] && echo "[setup] email from $DIR/config.json" >&2
  fi
  if [[ -z "$email" && -f "$CONFIG_DIR/.installed" ]]; then
    email="$(awk -F= '/^email=/{print $2; exit}' "$CONFIG_DIR/.installed" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ -n "$email" ]] && echo "[setup] email from $CONFIG_DIR/.installed" >&2
  fi
  if [[ -z "$email" ]]; then
    if [[ ! -t 0 ]]; then
      echo "[setup] ERROR: no email found. Set MEET_BRIDGE_EMAIL or write $CONFIG_DIR/email" >&2
      echo "[setup] Refusing to hang on non-TTY without email." >&2
      return 2
    fi
    printf 'Meet/bot Google account email: '
    read -r email
    email="$(echo "$email" | tr -d '[:space:]')"
    [[ -n "$email" ]] || { echo "[setup] ERROR: email required" >&2; return 2; }
  fi
  REPLY_EMAIL="$email"
  return 0
}

REPLY_EMAIL=""
resolve_email || exit $?
email="$REPLY_EMAIL"
printf '%s\n' "$email" > "$CONFIG_DIR/email"
chmod 600 "$CONFIG_DIR/email" 2>/dev/null || true
printf 'email=%s\ninstalled_at=%s\n' "$email" "$(date -Iseconds 2>/dev/null || date)" > "$CONFIG_DIR/.installed"
chmod 600 "$CONFIG_DIR/.installed" 2>/dev/null || true

python3 - "$email" "$CHROME_PROFILE_DIR" "$CONFIG_DIR/config.json" "$DIR/config.json" <<'PY'
import json, sys
email, chrome, dest1, dest2 = sys.argv[1:5]
cfg = {
  "email": email,
  "chromeUserDataDir": chrome,
  "mouthSink": "meet-mouth",
  "mouthMic": "meet-mouth-mic",
  "earsSink": "meet-ears",
  "earsMic": "meet-ears-mic",
}
text = json.dumps(cfg, indent=2) + "\n"
for path in (dest1, dest2):
    with open(path, "w") as f:
        f.write(text)
print(f"[setup] email={email}")
print(f"[setup] chrome user-data-dir={chrome}")
print(f"[setup] wrote {dest1}")
PY

echo "[setup] Chrome profile dir ready (empty until first launch)."
echo "[setup] Sign in once: google-chrome --user-data-dir=\"$CHROME_PROFILE_DIR\""
