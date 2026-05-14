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

cleanup() {
  if [[ "${was_running}" != "true" && "${TRELLIS_SMOKE_KEEP_RUNNING:-0}" != "1" ]]; then
    "${SCRIPT_DIR}/trellis_stop.sh" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

server_info="$(trellis_probe_url "${TRELLIS_SERVER_URL}/server_info")"
printf '%s\n' "${server_info}"

python3 - <<'PY' "${server_info}" "${TRELLIS_GGUF_QUANT}"
import json
import sys

payload = json.loads(sys.argv[1])
expected_quant = sys.argv[2]
backend = payload.get("backend")
model_path = payload.get("model_path")
subfolder = payload.get("subfolder")
status = payload.get("status")

if backend != "TRELLIS.2-GGUF":
    raise SystemExit(f"Unexpected backend in /server_info: {backend!r}")
if model_path != "Aero-Ex/Trellis2-GGUF":
    raise SystemExit(f"Unexpected model path in /server_info: {model_path!r}")
if subfolder != f"gguf/{expected_quant}":
    raise SystemExit(f"Unexpected GGUF subfolder in /server_info: {subfolder!r}")
if status not in {"ok", "ready"}:
    raise SystemExit(f"Unexpected status in /server_info: {status!r}")
PY

echo "SMOKE TEST PASSED"
echo "SUCCESS: TRELLIS.2 answered /server_info with backend=TRELLIS.2-GGUF model_path=Aero-Ex/Trellis2-GGUF subfolder=gguf/${TRELLIS_GGUF_QUANT}."
