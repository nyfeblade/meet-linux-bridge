#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$DIR/lib.sh"
ensure_tools
cmd="${1:-status}"
case "$cmd" in
  create|on) create_devices ;;
  destroy|off|teardown) destroy_devices ;;
  status) status_devices ;;
  *) echo "usage: $0 create|destroy|status" >&2; exit 2 ;;
esac
