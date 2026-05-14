#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TRELLIS_INSTALL_ROOT="${TRELLIS_INSTALL_ROOT:-${NYMPHS3D_TRELLIS_DIR:-$HOME/TRELLIS.2}}"
TRELLIS_VENV_DIR="${TRELLIS_VENV_DIR:-$TRELLIS_INSTALL_ROOT/.venv}"
NYMPHS_DATA_ROOT="${NYMPHS_DATA_ROOT:-$HOME/NymphsData}"
TRELLIS_CONFIG_DIR="${TRELLIS_CONFIG_DIR:-$NYMPHS_DATA_ROOT/config/trellis}"
TRELLIS_PRESET_FILE="${TRELLIS_PRESET_FILE:-$TRELLIS_CONFIG_DIR/model-preset.env}"
TRELLIS_OUTPUT_DIR="${TRELLIS_OUTPUT_DIR:-$NYMPHS_DATA_ROOT/outputs/trellis}"
TRELLIS_LOG_DIR="${TRELLIS_LOG_DIR:-$NYMPHS_DATA_ROOT/logs/trellis}"
TRELLIS_PID_FILE="${TRELLIS_PID_FILE:-$TRELLIS_LOG_DIR/trellis.pid}"
TRELLIS_HOST="${TRELLIS_HOST:-127.0.0.1}"
TRELLIS_PORT="${TRELLIS_PORT:-8095}"
TRELLIS_SERVER_URL="${TRELLIS_SERVER_URL:-http://${TRELLIS_HOST}:${TRELLIS_PORT}}"
TRELLIS_DEFAULT_GGUF_QUANT="Q5_K_M"
TRELLIS_TORCH_INDEX_URL="${TRELLIS_TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu130}"

TRELLIS_SOURCE_COMMIT="${TRELLIS_SOURCE_COMMIT:-5565d240c4a494caaf9ece7a554542b76ffa36d3}"
TRELLIS2_GGUF_REPO_URL="${TRELLIS2_GGUF_REPO_URL:-https://github.com/Aero-Ex/ComfyUI-Trellis2-GGUF.git}"
TRELLIS2_GGUF_REPO_REF="${TRELLIS2_GGUF_REPO_REF:-ed7245cba449c79e0a6703b7f09c0590328b4f77}"
COMFYUI_GGUF_REPO_URL="${COMFYUI_GGUF_REPO_URL:-https://github.com/city96/ComfyUI-GGUF.git}"
COMFYUI_GGUF_REPO_REF="${COMFYUI_GGUF_REPO_REF:-6ea2651e7df66d7585f6ffee804b20e92fb38b8a}"
UTILS3D_REF="${UTILS3D_REF:-9a4eb15e4021b67b12c460c7057d642626897ec8}"
TRELLIS_CUMESH_REF="${TRELLIS_CUMESH_REF:-cf1a2f07304b5fe388ed86a16e4a0474599df914}"
TRELLIS_FLEXGEMM_REF="${TRELLIS_FLEXGEMM_REF:-6dd94a859c26ee8246888502eada3dd8ad85532e}"
TRELLIS_NVDIFFRAST_REF="${TRELLIS_NVDIFFRAST_REF:-253ac4fcea7de5f396371124af597e6cc957bfae}"
TRELLIS_GGUF_RUNTIME_DIR="${TRELLIS_GGUF_RUNTIME_DIR:-$TRELLIS_INSTALL_ROOT/.cache/trellis-gguf-runtime}"

preset_quant=""
if [[ -f "${TRELLIS_PRESET_FILE}" ]]; then
  while IFS='=' read -r key value; do
    case "${key}" in
      TRELLIS_GGUF_QUANT)
        case "${value}" in
          Q4_K_M|Q5_K_M|Q6_K|Q8_0) preset_quant="${value}" ;;
        esac
        ;;
    esac
  done < "${TRELLIS_PRESET_FILE}"
fi
TRELLIS_GGUF_QUANT="${TRELLIS_GGUF_QUANT:-${preset_quant:-$TRELLIS_DEFAULT_GGUF_QUANT}}"

export OPENCV_IO_ENABLE_OPENEXR="${OPENCV_IO_ENABLE_OPENEXR:-1}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-0}"
export NYMPHS3D_HF_CACHE_DIR="${NYMPHS3D_HF_CACHE_DIR:-$NYMPHS_DATA_ROOT/cache/huggingface}"
export HF_HOME="${HF_HOME:-$NYMPHS_DATA_ROOT/cache/huggingface-home}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$NYMPHS3D_HF_CACHE_DIR}"
export U2NET_HOME="${U2NET_HOME:-$NYMPHS_DATA_ROOT/models/rembg}"
export TRELLIS_OUTPUT_DIR
export TRELLIS_GGUF_QUANT

if [[ -d /usr/local/cuda-13.0 ]]; then
  export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-13.0}"
  export PATH="${CUDA_HOME}/bin:${PATH}"
  export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
fi

trellis_ensure_data_dirs() {
  mkdir -p "${TRELLIS_LOG_DIR}" "${TRELLIS_OUTPUT_DIR}" "${TRELLIS_CONFIG_DIR}" "${NYMPHS3D_HF_CACHE_DIR}" "${U2NET_HOME}"
}

trellis_python() {
  printf '%s\n' "${TRELLIS_VENV_DIR}/bin/python"
}

trellis_pip() {
  printf '%s\n' "${TRELLIS_VENV_DIR}/bin/pip"
}

trellis_is_running() {
  if [[ -f "${TRELLIS_PID_FILE}" ]]; then
    local pid
    pid="$(cat "${TRELLIS_PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

trellis_probe_url() {
  local url="${1}"
  python3 - "${url}" <<'PY'
import sys
from urllib.request import urlopen

try:
    with urlopen(sys.argv[1], timeout=2) as response:
        print(response.read().decode("utf-8", errors="replace"))
except Exception as exc:
    raise SystemExit(str(exc))
PY
}

trellis_site_packages_dir() {
  "$(trellis_python)" - <<'PY'
import site

paths = [p for p in site.getsitepackages() if p.endswith("site-packages")]
if not paths:
    raise SystemExit("Could not resolve site-packages for the TRELLIS venv.")
print(paths[0])
PY
}
