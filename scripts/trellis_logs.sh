#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

echo "logs=${TRELLIS_LOG_DIR}"
if [[ -f "${TRELLIS_LOG_DIR}/trellis-server.log" ]]; then
  tail -n "${TRELLIS_LOG_LINES:-160}" "${TRELLIS_LOG_DIR}/trellis-server.log"
else
  echo "No TRELLIS.2 server log yet."
fi
