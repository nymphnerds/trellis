#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

was_running=false
if trellis_is_running; then
  was_running=true
else
  "${SCRIPT_DIR}/trellis_start.sh"
fi

trellis_probe_url "${TRELLIS_SERVER_URL}/server_info"

if [[ "${was_running}" != "true" && "${TRELLIS_SMOKE_KEEP_RUNNING:-0}" != "1" ]]; then
  "${SCRIPT_DIR}/trellis_stop.sh"
fi
