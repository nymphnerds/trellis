#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

installed=false
runtime_present=false
data_present=false
env_ready=false
adapter_ready=false
runtime_ready=false
models_ready=unknown
running=false
version=not-installed
health=unavailable
state=available
marker="${TRELLIS_INSTALL_ROOT}/.nymph-module-version"
detail="Not installed."

if [[ -f "${marker}" ]]; then
  installed=true
  runtime_present=true
  version="$(head -n 1 "${marker}" 2>/dev/null || true)"
  [[ -n "${version}" ]] || version=unknown
  detail="Source installed."
fi

if [[ -d "${TRELLIS_OUTPUT_DIR}" && -n "$(find "${TRELLIS_OUTPUT_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]] ||
   [[ -d "${TRELLIS_INSTALL_ROOT}/outputs" && -n "$(find "${TRELLIS_INSTALL_ROOT}/outputs" -mindepth 1 -print -quit 2>/dev/null)" ]] ||
   [[ -d "${TRELLIS_LOG_DIR}" && -n "$(find "${TRELLIS_LOG_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]] ||
   [[ -d "${TRELLIS_INSTALL_ROOT}/logs" && -n "$(find "${TRELLIS_INSTALL_ROOT}/logs" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
  data_present=true
fi

if [[ "${installed}" == "true" && -x "$(trellis_python)" ]]; then
  env_ready=true
  detail="Runtime environment present."
fi

if [[ "${installed}" == "true" && -f "${TRELLIS_INSTALL_ROOT}/scripts/api_server_trellis_gguf.py" && -f "${TRELLIS_INSTALL_ROOT}/scripts/trellis_gguf_common.py" ]]; then
  adapter_ready=true
fi

if [[ "${installed}" == "true" ]] && trellis_is_running; then
  running=true
  if trellis_probe_url "${TRELLIS_SERVER_URL}/server_info" >/dev/null 2>&1; then
    health=ok
  else
    health=unreachable
  fi
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
    if [[ "${health}" != "unreachable" ]]; then
      health=ok
    fi
    detail="Runtime imports are ready."
  else
    health=degraded
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
    if [[ "${health}" != "unreachable" ]]; then
      health=ok
    fi
    detail="Runtime and cached GGUF model files are ready."
  else
    models_ready=false
    health=model-download-needed
    detail="Runtime exists, but cached GGUF model files are incomplete for ${TRELLIS_GGUF_QUANT}. Use Fetch Models to download the selected Aero-Ex/Trellis2-GGUF quant, the microsoft/TRELLIS.2-4B support checkpoint, and rembg u2net."
  fi
fi

if [[ "${installed}" == "true" && "${running}" == "true" ]]; then
  state=running
elif [[ "${installed}" == "true" && "${env_ready}" != "true" ]]; then
  state=needs_attention
  health=degraded
  detail="TRELLIS runtime files are installed, but the Python runtime is missing."
elif [[ "${installed}" == "true" && "${adapter_ready}" != "true" ]]; then
  state=needs_attention
  health=degraded
  detail="TRELLIS runtime files are installed, but the GGUF adapter scripts are missing."
elif [[ "${installed}" == "true" && ( "${health}" == "degraded" || "${health}" == "model-download-needed" ) ]]; then
  state=needs_attention
elif [[ "${installed}" == "true" ]]; then
  state=installed
elif [[ "${data_present}" == "true" ]]; then
  detail="TRELLIS preserved data remains, but runtime files are not installed."
fi

cat <<EOF
id=trellis
name=TRELLIS.2
installed=${installed}
runtime_present=${runtime_present}
data_present=${data_present}
version=${version}
env_ready=${env_ready}
adapter_ready=${adapter_ready}
runtime_ready=${runtime_ready}
models_ready=${models_ready}
running=${running}
state=${state}
health=${health}
url=${TRELLIS_SERVER_URL}
install_root=${TRELLIS_INSTALL_ROOT}
venv=${TRELLIS_VENV_DIR}
logs_dir=${TRELLIS_LOG_DIR}
outputs_dir=${TRELLIS_OUTPUT_DIR}
config_dir=${TRELLIS_CONFIG_DIR}
hf_cache_dir=${NYMPHS3D_HF_CACHE_DIR}
u2net_dir=${U2NET_HOME}
preset_file=${TRELLIS_PRESET_FILE}
quant=${TRELLIS_GGUF_QUANT}
marker=${marker}
detail=${detail}
EOF
