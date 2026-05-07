#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

installed=false
env_ready=false
adapter_ready=false
runtime_ready=false
models_ready=unknown
running=false
detail="Not installed."

if [[ -f "${TRELLIS_INSTALL_ROOT}/trellis2/__init__.py" ]]; then
  installed=true
  detail="Source installed."
fi

if [[ -x "$(trellis_python)" ]]; then
  env_ready=true
  detail="Runtime environment present."
fi

if [[ -f "${TRELLIS_INSTALL_ROOT}/scripts/api_server_trellis_gguf.py" && -f "${TRELLIS_INSTALL_ROOT}/scripts/trellis_gguf_common.py" ]]; then
  adapter_ready=true
fi

if trellis_is_running; then
  running=true
fi

if [[ "${env_ready}" == "true" && "${adapter_ready}" == "true" ]]; then
  if (
    cd "${TRELLIS_INSTALL_ROOT}"
    "$(trellis_python)" -m py_compile scripts/api_server_trellis_gguf.py scripts/trellis_gguf_common.py >/dev/null 2>&1
    "$(trellis_python)" - <<'PY' >/dev/null 2>&1
import importlib

for module_name in ("trellis2_gguf", "gguf", "rembg"):
    importlib.import_module(module_name)
PY
  ); then
    runtime_ready=true
    detail="Runtime imports are ready."
  else
    detail="Runtime exists, but GGUF packages are missing."
  fi
fi

if [[ "${runtime_ready}" == "true" ]]; then
  if (
    cd "${TRELLIS_INSTALL_ROOT}"
    "$(trellis_python)" - <<'PY' >/dev/null 2>&1
import sys
from pathlib import Path

sys.path.insert(0, str(Path.cwd() / "scripts"))
from trellis_gguf_common import ensure_required_support_models, gguf_quant_is_available, resolve_gguf_model_root, resolve_gguf_quant

quant = resolve_gguf_quant()
root = resolve_gguf_model_root(local_files_only=True, quant=quant, include_texture=True)
ensure_required_support_models(local_files_only=True)
if not gguf_quant_is_available(root, quant, include_texture=True):
    raise RuntimeError("missing TRELLIS GGUF model files")
PY
  ); then
    models_ready=true
    detail="Runtime and cached GGUF model files are ready."
  else
    models_ready=false
    detail="Runtime exists, but cached GGUF model files are incomplete."
  fi
fi

cat <<EOF
id=trellis
name=TRELLIS.2
installed=${installed}
env_ready=${env_ready}
adapter_ready=${adapter_ready}
runtime_ready=${runtime_ready}
models_ready=${models_ready}
running=${running}
url=${TRELLIS_SERVER_URL}
install_root=${TRELLIS_INSTALL_ROOT}
venv=${TRELLIS_VENV_DIR}
logs=${TRELLIS_LOG_DIR}
quant=${TRELLIS_GGUF_QUANT}
detail=${detail}
EOF
