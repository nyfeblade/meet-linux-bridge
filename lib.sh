#!/usr/bin/env bash
# Shared helpers for meet-mouth / meet-ears PipeWire bridge (Pulse compat).
set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="$SPIKE_DIR/runtime"
MODULES_FILE="$RUNTIME/modules.env"
ROUTE_PREV="$RUNTIME/route-prev.env"
MOUTH_SINK="${MOUTH_SINK:-meet-mouth}"
EARS_SINK="${EARS_SINK:-meet-ears}"
MOUTH_MIC="${MOUTH_MIC:-meet-mouth-mic}"
EARS_MIC="${EARS_MIC:-meet-ears-mic}"

mkdir -p "$RUNTIME"

have_sink() { pactl list short sinks 2>/dev/null | awk "{print \$2}" | grep -qx "$1"; }
have_source() { pactl list short sources 2>/dev/null | awk "{print \$2}" | grep -qx "$1"; }

load_mod() {
  local name="$1"; shift
  local id
  id="$(pactl load-module "$@")"
  echo "${name}=${id}" >> "$MODULES_FILE"
  echo "$id"
}

devices_present() {
  have_sink "$MOUTH_SINK" && have_sink "$EARS_SINK" && have_source "$MOUTH_MIC" && have_source "$EARS_MIC"
}

create_devices() {
  if devices_present; then
    echo "[devices] already present: $MOUTH_SINK / $EARS_SINK / $MOUTH_MIC / $EARS_MIC"
    return 0
  fi
  destroy_devices >/dev/null 2>&1 || true
  : > "$MODULES_FILE"

  echo "[devices] creating null sinks + remapped mics..."
  load_mod mouth_sink module-null-sink \
    sink_name="$MOUTH_SINK" \
    sink_properties="device.description=$MOUTH_SINK" \
    rate=48000 channels=2 >/dev/null

  load_mod ears_sink module-null-sink \
    sink_name="$EARS_SINK" \
    sink_properties="device.description=$EARS_SINK" \
    rate=48000 channels=2 >/dev/null

  sleep 0.5

  if ! have_source "${MOUTH_SINK}.monitor"; then
    echo "[devices] ERROR: ${MOUTH_SINK}.monitor missing" >&2
    return 1
  fi
  if ! have_source "${EARS_SINK}.monitor"; then
    echo "[devices] ERROR: ${EARS_SINK}.monitor missing" >&2
    return 1
  fi

  load_mod mouth_mic module-remap-source \
    master="${MOUTH_SINK}.monitor" \
    source_name="$MOUTH_MIC" \
    source_properties="device.description=$MOUTH_MIC" \
    channels=2 >/dev/null

  load_mod ears_mic module-remap-source \
    master="${EARS_SINK}.monitor" \
    source_name="$EARS_MIC" \
    source_properties="device.description=$EARS_MIC" \
    channels=2 >/dev/null

  sleep 0.3
  for s in "$MOUTH_SINK" "$EARS_SINK"; do
    pactl set-sink-mute "$s" 0 || true
    pactl set-sink-volume "$s" 100% || true
  done
  for s in "$MOUTH_MIC" "$EARS_MIC" "${MOUTH_SINK}.monitor" "${EARS_SINK}.monitor"; do
    pactl set-source-mute "$s" 0 2>/dev/null || true
    pactl set-source-volume "$s" 100% 2>/dev/null || true
  done

  if ! devices_present; then
    echo "[devices] ERROR: create incomplete" >&2
    pactl list short sinks >&2 || true
    pactl list short sources >&2 || true
    return 1
  fi
  echo "[devices] OK: sinks=$MOUTH_SINK,$EARS_SINK  mics=$MOUTH_MIC,$EARS_MIC"
}

destroy_devices() {
  if [[ -f "$ROUTE_PREV" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTE_PREV"
    if [[ -n "${PREV_DEFAULT_SINK:-}" ]]; then
      pactl set-default-sink "$PREV_DEFAULT_SINK" 2>/dev/null || true
    fi
    rm -f "$ROUTE_PREV"
  fi

  if [[ -f "$MODULES_FILE" ]]; then
    tac "$MODULES_FILE" 2>/dev/null | while IFS="=" read -r _name id; do
      [[ -n "${id:-}" ]] && pactl unload-module "$id" 2>/dev/null || true
    done
    rm -f "$MODULES_FILE"
  fi

  for sink in "$MOUTH_SINK" "$EARS_SINK"; do
    if have_sink "$sink"; then
      mid="$(pactl list modules short 2>/dev/null | awk -v s="sink_name=$sink" "\$0 ~ s {print \$1; exit}")"
      [[ -n "${mid:-}" ]] && pactl unload-module "$mid" 2>/dev/null || true
    fi
  done
  for src in "$MOUTH_MIC" "$EARS_MIC"; do
    if have_source "$src"; then
      mid="$(pactl list modules short 2>/dev/null | awk -v s="source_name=$src" "\$0 ~ s {print \$1; exit}")"
      [[ -n "${mid:-}" ]] && pactl unload-module "$mid" 2>/dev/null || true
    fi
  done
  sleep 0.2
  echo "[devices] destroyed (or already gone)"
}

status_devices() {
  echo "=== sinks ==="
  pactl list short sinks | awk "{print \$1, \$2, \$5}"
  echo "=== sources ==="
  pactl list short sources | awk "{print \$1, \$2, \$5}"
  echo "=== defaults ==="
  echo "default-sink:   $(pactl get-default-sink)"
  echo "default-source: $(pactl get-default-source)"
  echo "=== bridge ==="
  if devices_present; then
    echo "devices: PRESENT ($MOUTH_SINK / $EARS_SINK / $MOUTH_MIC / $EARS_MIC)"
  else
    echo "devices: MISSING (run: ./devices.sh create)"
  fi
  if [[ -f "$ROUTE_PREV" ]]; then
    # shellcheck disable=SC1090
    source "$ROUTE_PREV"
    echo "route: ON (saved default sink was ${PREV_DEFAULT_SINK:-?})"
  else
    echo "route: OFF"
  fi
}

# Peak linear 0..1 on Pulse source over secs (ffmpeg astats).
meter_source() {
  local src="$1"
  local secs="${2:-2}"
  local err peaks
  err="$(ffmpeg -hide_banner -nostats -f pulse -i "$src" -t "$secs" \
    -af "astats=metadata=0:reset=0" -f null - 2>&1 || true)"
  peaks="$(printf "%s\n" "$err" | sed -n "s/.*Peak level dB:[[:space:]]*\\(-inf\\|-*[0-9.][0-9.]*\\).*/\\1/p")"
  if [[ -z "$peaks" ]]; then
    echo "-1"
    return 0
  fi
  printf "%s\n" "$peaks" | python3 -c "
import sys, math
vals=[]
for line in sys.stdin:
    s=line.strip()
    if not s or s==\"-inf\": continue
    try: vals.append(float(s))
    except: pass
if not vals:
    print(\"0\")
else:
    db=max(vals)
    print(f\"{10**(db/20):.6f}\")
"
}

play_tone() {
  local sink="$1"
  local secs="${2:-2}"
  local hz="${3:-440}"
  ffmpeg -hide_banner -loglevel error -re \
    -f lavfi -i "sine=frequency=${hz}:sample_rate=48000:duration=${secs}" \
    -f pulse -device "$sink" -ac 2 -
}

ensure_tools() {
  local missing=()
  command -v pactl >/dev/null || missing+=(pactl)
  command -v ffmpeg >/dev/null || missing+=(ffmpeg)
  command -v python3 >/dev/null || missing+=(python3)
  if ((${#missing[@]})); then
    echo "missing tools: ${missing[*]}" >&2
    return 1
  fi
}
