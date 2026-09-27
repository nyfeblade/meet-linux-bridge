#!/usr/bin/env bash
# One-command install for meet-linux-bridge on clean Linux VMs.
# Detects Fedora/RHEL vs Debian/Ubuntu. Idempotent.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${MEET_BRIDGE_CONFIG_DIR:-$HOME/.config/meet-bridge}"
CHROME_PROFILE_DIR="${MEET_BRIDGE_CHROME_DIR:-$HOME/.config/meet-bridge/chrome-profile}"
NONINTERACTIVE=0
[[ "${1:-}" == "--noninteractive" || -n "${MEET_BRIDGE_EMAIL:-}" ]] && NONINTERACTIVE=1

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install] WARN: %s\n' "$*" >&2; }
die()  { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

need_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
  elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "need root or sudo to install packages"
  fi
}

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID_LIKE:-}${ID:-}" in
      *fedora*|*rhel*|*centos*|*rocky*|*almalinux*) echo fedora ;;
      *debian*|*ubuntu*) echo debian ;;
      *)
        case "${ID:-}" in
          fedora|rhel|centos|rocky|almalinux) echo fedora ;;
          debian|ubuntu|linuxmint|pop) echo debian ;;
          *) echo unknown ;;
        esac
        ;;
    esac
  else
    echo unknown
  fi
}

pkg_install_fedora() {
  need_sudo
  local pkgs=(pipewire pipewire-pulseaudio pulseaudio-utils ffmpeg python3)
  # Some Fedora spins already have these; dnf is idempotent enough.
  log "Fedora/RHEL: ensuring ${pkgs[*]} ..."
  $SUDO dnf install -y "${pkgs[@]}" || warn "dnf install returned non-zero; continuing"
  # Chrome: try RPM if missing
  if ! command -v google-chrome >/dev/null 2>&1 && ! command -v google-chrome-stable >/dev/null 2>&1 \
     && ! command -v chromium-browser >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1; then
    log "Chrome not found; attempting google-chrome-stable (may need manual repo)..."
    if $SUDO dnf install -y google-chrome-stable 2>/dev/null; then
      log "google-chrome-stable installed"
    else
      warn "Chrome not installable via dnf. Install manually: https://www.google.com/chrome/"
      warn "Meet join automation will need Chrome or Chromium."
    fi
  fi
}

pkg_install_debian() {
  need_sudo
  log "Debian/Ubuntu: apt-get update ..."
  $SUDO apt-get update -qq || warn "apt-get update failed; continuing"
  local pkgs=(pipewire pipewire-pulse pulseaudio-utils ffmpeg python3)
  # pulseaudio-utils provides pactl; pipewire-pulse provides the Pulse compat server
  log "installing ${pkgs[*]} ..."
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${pkgs[@]}" \
    || warn "apt install returned non-zero; continuing"
  if ! command -v google-chrome >/dev/null 2>&1 && ! command -v google-chrome-stable >/dev/null 2>&1 \
     && ! command -v chromium-browser >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1; then
    log "Chrome not found; trying chromium ..."
    if DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y chromium 2>/dev/null \
       || DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y chromium-browser 2>/dev/null; then
      log "Chromium installed"
    else
      warn "Chrome/Chromium not installable via apt. Install Google Chrome manually if needed."
    fi
  fi
}

ensure_pulse_session() {
  # Start a user PipeWire/Pulse session if pactl is missing a server.
  # Works on cloud VMs without systemd --user (dbus-launch + XDG_RUNTIME_DIR).
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-$(id -u)}"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    if [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    elif command -v dbus-launch >/dev/null 2>&1; then
      # shellcheck disable=SC2046
      eval "$(dbus-launch --sh-syntax)"
      log "started session dbus"
    elif command -v dbus-daemon >/dev/null 2>&1; then
      dbus-daemon --session --address="unix:path=$XDG_RUNTIME_DIR/bus" --fork 2>/dev/null || true
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    fi
  fi

  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    log "Pulse/PipeWire session OK ($(pactl get-default-sink 2>/dev/null || echo '?'))"
    return 0
  fi
  log "No live Pulse server; trying to start pipewire-pulse / pulseaudio ..."
  if command -v pipewire >/dev/null 2>&1; then
    if ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
      nohup pipewire >/tmp/meet-bridge-pipewire.log 2>&1 &
      sleep 0.8
    fi
    if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
      nohup wireplumber >/tmp/meet-bridge-wireplumber.log 2>&1 &
      sleep 0.8
    fi
    if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
      nohup pipewire-pulse >/tmp/meet-bridge-pipewire-pulse.log 2>&1 &
      sleep 1.0
    fi
  elif command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio --start --exit-idle-time=-1 >/tmp/meet-bridge-pulse.log 2>&1 || true
    sleep 0.5
  fi
  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    log "Pulse session started ($(pactl get-default-sink 2>/dev/null || echo '?'))"
    return 0
  fi
  warn "pactl still cannot talk to a server. Selftest may FAIL until PipeWire/Pulse is running."
  warn "hint: export XDG_RUNTIME_DIR and start dbus-launch; then re-run ./selftest"
  return 0
}

ensure_node_playwright() {
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    warn "node/npm missing — Meet join automation (scripts/join-meet.mjs) needs Node 18+"
    local distro
    distro="$(detect_distro)"
    need_sudo
    if [[ "$distro" == "fedora" ]]; then
      $SUDO dnf install -y nodejs npm 2>/dev/null || warn "could not install nodejs"
    elif [[ "$distro" == "debian" ]]; then
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y nodejs npm 2>/dev/null || warn "could not install nodejs"
    fi
  fi
  if command -v npm >/dev/null 2>&1 && [[ -f "$DIR/package.json" ]]; then
    log "npm install (playwright) ..."
    (cd "$DIR" && npm install --no-fund --no-audit) || warn "npm install failed"
    # Browsers: prefer system Chrome; still fetch chromium for playwright fallback
    if [[ -d "$DIR/node_modules/playwright" ]]; then
      (cd "$DIR" && npx playwright install chromium 2>/dev/null) || warn "playwright browser install skipped/failed"
    fi
  fi
}

resolve_email() {
  # Check-first, never ask twice.
  # Order: MEET_BRIDGE_EMAIL → ~/.config/meet-bridge/email → config.json →
  #        install marker → interactive prompt (TTY only).
  local email=""
  if [[ -n "${MEET_BRIDGE_EMAIL:-}" ]]; then
    email="$(echo "$MEET_BRIDGE_EMAIL" | tr -d "[:space:]")"
    echo "[install] email from MEET_BRIDGE_EMAIL" >&2
  fi
  if [[ -z "$email" && -f "$CONFIG_DIR/email" ]]; then
    email="$(tr -d "[:space:]" < "$CONFIG_DIR/email")"
    [[ -n "$email" ]] && echo "[install] email from $CONFIG_DIR/email" >&2
  fi
  if [[ -z "$email" && -f "$CONFIG_DIR/config.json" ]]; then
    email="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get("email","") or "")" "$CONFIG_DIR/config.json" 2>/dev/null || true)"
    email="$(echo "$email" | tr -d "[:space:]")"
    [[ -n "$email" ]] && echo "[install] email from $CONFIG_DIR/config.json" >&2
  fi
  if [[ -z "$email" && -f "$DIR/config.json" ]]; then
    email="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get("email","") or "")" "$DIR/config.json" 2>/dev/null || true)"
    email="$(echo "$email" | tr -d "[:space:]")"
    [[ -n "$email" ]] && echo "[install] email from $DIR/config.json" >&2
  fi
  if [[ -z "$email" && -f "$CONFIG_DIR/.installed" ]]; then
    email="$(awk -F= "/^email=/{print \$2; exit}" "$CONFIG_DIR/.installed" 2>/dev/null | tr -d "[:space:]" || true)"
    [[ -n "$email" ]] && echo "[install] email from $CONFIG_DIR/.installed" >&2
  fi
  if [[ -z "$email" ]]; then
    if [[ "$NONINTERACTIVE" -eq 1 ]] || [[ ! -t 0 ]]; then
      echo "[install] ERROR: no email found. Set MEET_BRIDGE_EMAIL or write $CONFIG_DIR/email" >&2
      echo "[install] Noninteractive/no-TTY install will not hang waiting for input." >&2
      exit 2
    fi
    printf "Meet/bot Google account email: "
    read -r email
    email="$(echo "$email" | tr -d "[:space:]")"
    [[ -n "$email" ]] || { echo "[install] ERROR: email required" >&2; exit 2; }
  fi
  printf "%s\n" "$email"
}

setup_config() {
  mkdir -p "$CONFIG_DIR" "$CHROME_PROFILE_DIR" "$DIR/runtime"
  local email
  email="$(resolve_email)"
  # Store on first capture / refresh (never re-prompt next time)
  printf "%s\n" "$email" > "$CONFIG_DIR/email"
  chmod 600 "$CONFIG_DIR/email" 2>/dev/null || true
  printf "email=%s\ninstalled_at=%s\n" "$email" "$(date -Iseconds 2>/dev/null || date)" > "$CONFIG_DIR/.installed"
  chmod 600 "$CONFIG_DIR/.installed" 2>/dev/null || true

  cat > "$CONFIG_DIR/config.json" << EOF
{
  "email": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$email"),
  "chromeUserDataDir": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$CHROME_PROFILE_DIR"),
  "mouthSink": "meet-mouth",
  "mouthMic": "meet-mouth-mic",
  "earsSink": "meet-ears",
  "earsMic": "meet-ears-mic"
}
EOF
  cp "$CONFIG_DIR/config.json" "$DIR/config.json" 2>/dev/null || true
  log "config: email=$email"
  log "config: chrome user-data-dir=$CHROME_PROFILE_DIR (empty until first Chrome launch)"
  log "config: stored at $CONFIG_DIR/ (re-runs reuse; set MEET_BRIDGE_EMAIL to override)"
}

create_bridge_devices() {
  if ! command -v pactl >/dev/null 2>&1; then
    warn "pactl missing — skip device create (install pulseaudio-utils)"
    return 0
  fi
  if ! pactl info >/dev/null 2>&1; then
    warn "no Pulse server — skip device create"
    return 0
  fi
  log "creating virtual devices (idempotent) ..."
  "$DIR/devices.sh" create
}

run_selftest() {
  if ! command -v pactl >/dev/null 2>&1 || ! pactl info >/dev/null 2>&1; then
    warn "skipping selftest (no Pulse server)"
    return 0
  fi
  log "running selftest ..."
  if "$DIR/selftest"; then
    log "SELFTEST PASS"
    return 0
  else
    warn "SELFTEST FAIL — see output above"
    return 1
  fi
}

main() {
  log "meet-linux-bridge install from $DIR"
  local distro
  distro="$(detect_distro)"
  log "distro family: $distro"
  case "$distro" in
    fedora) pkg_install_fedora ;;
    debian) pkg_install_debian ;;
    *)
      warn "unknown distro; attempting to ensure tools without package manager"
      ;;
  esac

  # Verify core tools
  local missing=()
  command -v pactl >/dev/null || missing+=(pactl)
  command -v ffmpeg >/dev/null || missing+=(ffmpeg)
  command -v python3 >/dev/null || missing+=(python3)
  if ((${#missing[@]})); then
    warn "still missing after install: ${missing[*]}"
  else
    log "tools OK: pactl ffmpeg python3"
  fi

  ensure_pulse_session
  setup_config
  ensure_node_playwright
  create_bridge_devices || true

  local st=0
  run_selftest || st=$?

  echo
  log "=== next steps ==="
  log "1. ./route on"
  log "2. Grok Bot Settings > Microphone = meet-ears-mic"
  log "3. Join Meet: node scripts/join-meet.mjs <meet-url>"
  log "   Meet mic = meet-mouth-mic | Meet speakers = meet-ears"
  log "4. Or manually: google-chrome --user-data-dir=\"$CHROME_PROFILE_DIR\" <meet-url>"
  log "config email: $(cat "$CONFIG_DIR/email" 2>/dev/null || echo '?')"
  if [[ "$st" -ne 0 ]]; then
    warn "install finished but selftest FAILED"
    exit "$st"
  fi
  log "done."
}

main "$@"
