#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

if trellis_is_running; then
  echo "TRELLIS.2 is already running at ${TRELLIS_SERVER_URL}"
  exit 0
fi

if [[ ! -x "$(trellis_python)" ]]; then
  echo "TRELLIS.2 runtime is missing. Run scripts/install_trellis.sh first." >&2
  exit 1
fi

if [[ ! -f "${TRELLIS_INSTALL_ROOT}/scripts/api_server_trellis_gguf.py" ]]; then
  echo "TRELLIS.2 GGUF adapter is missing. Run scripts/install_trellis.sh first." >&2
  exit 1
fi

trellis_ensure_data_dirs
log_file="${TRELLIS_LOG_DIR}/trellis-server.log"
echo "Starting TRELLIS.2 at ${TRELLIS_SERVER_URL}"
(
  cd "${TRELLIS_INSTALL_ROOT}"
  nohup "$(trellis_python)" -u scripts/api_server_trellis_gguf.py --host "${TRELLIS_HOST}" --port "${TRELLIS_PORT}" --gguf-quant "${TRELLIS_GGUF_QUANT}" >"${log_file}" 2>&1 &
  echo $! > "${TRELLIS_PID_FILE}"
)

for _ in $(seq 1 60); do
  if trellis_probe_url "${TRELLIS_SERVER_URL}/server_info" >/dev/null 2>&1; then
    echo "TRELLIS.2 started."
    exit 0
  fi
  sleep 1
done

echo "TRELLIS.2 did not answer before timeout. Check ${log_file}" >&2
exit 1
