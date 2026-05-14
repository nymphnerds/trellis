#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

requested_quant=""
download_all_quants=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quant|--model)
      if [[ $# -lt 2 ]]; then
        echo "$1 requires one of: Q4_K_M, Q5_K_M, Q6_K, Q8_0, all." >&2
        exit 2
      fi
      requested_quant="${2:-}"
      shift 2
      ;;
    --quant=*|--model=*)
      requested_quant="${1#*=}"
      shift
      ;;
    --hf_token|--hf-token)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        export NYMPHS3D_HF_TOKEN=""
        shift 1
      else
        export NYMPHS3D_HF_TOKEN="${2:-}"
        shift 2
      fi
      ;;
    --hf_token=*|--hf-token=*)
      export NYMPHS3D_HF_TOKEN="${1#*=}"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  trellis_fetch_models.sh --quant Q5_K_M
  trellis_fetch_models.sh --quant all

Downloads the selected TRELLIS.2 GGUF quant files from Aero-Ex/Trellis2-GGUF,
the required support checkpoint from microsoft/TRELLIS.2-4B, and the rembg
u2net background-removal model. Use --quant all only if Blender/addon workflows
need to switch between every supported quant later.

Supported TRELLIS.2 GGUF quants:
  Q4_K_M  - smallest download, lowest VRAM, fastest first test
  Q5_K_M  - recommended balance for most users
  Q6_K    - higher quality, larger download and more VRAM
  Q8_0    - largest local GGUF option, best fidelity if the GPU has room
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -n "${requested_quant}" ]]; then
  case "${requested_quant}" in
    all|all_quants|all-quants)
      download_all_quants=true
      ;;
    Q4_K_M|Q5_K_M|Q6_K|Q8_0)
      TRELLIS_GGUF_QUANT="${requested_quant}"
      export TRELLIS_GGUF_QUANT
      ;;
    *)
      echo "Unsupported TRELLIS.2 GGUF quant: ${requested_quant}." >&2
      echo "Expected one of: Q4_K_M, Q5_K_M, Q6_K, Q8_0, all." >&2
      exit 2
      ;;
  esac
fi

if [[ ! -x "$(trellis_python)" ]]; then
  echo "TRELLIS.2 runtime is missing. Run scripts/install_trellis.sh first." >&2
  exit 1
fi

save_trellis_model_preset() {
  mkdir -p "${TRELLIS_CONFIG_DIR}"
  {
    printf 'TRELLIS_GGUF_QUANT=%s\n' "${TRELLIS_GGUF_QUANT}"
    printf 'TRELLIS_GGUF_MODEL_REPO=%s\n' "Aero-Ex/Trellis2-GGUF"
    printf 'TRELLIS_SUPPORT_MODEL_REPO=%s\n' "microsoft/TRELLIS.2-4B"
  } > "${TRELLIS_PRESET_FILE}"
}

fetch_rembg_u2net() {
  "$(trellis_python)" - <<'PY'
import os
from pathlib import Path
from urllib.request import urlopen

model_dir = Path(os.environ.get("U2NET_HOME") or str(Path.home() / ".u2net")).expanduser()
model_dir.mkdir(parents=True, exist_ok=True)
model_path = model_dir / "u2net.onnx"
url = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"

if model_path.exists() and model_path.stat().st_size > 0:
    print(f"MODEL FETCH COMPLETE: step=3/3 rembg u2net already present path={model_path}", flush=True)
    raise SystemExit(0)

tmp_path = model_path.with_suffix(".onnx.tmp")
print(f"MODEL FETCH STARTED: step=3/3 repo=rembg/u2net path={model_path}", flush=True)
with urlopen(url, timeout=30) as response, open(tmp_path, "wb") as handle:
    total = int(response.headers.get("Content-Length") or 0)
    downloaded = 0
    next_report = 0
    while True:
        chunk = response.read(1024 * 1024)
        if not chunk:
            break
        handle.write(chunk)
        downloaded += len(chunk)
        if downloaded >= next_report:
            if total:
                percent = downloaded * 100 / total
                print(f"MODEL FETCH STATUS: step=3/3 rembg_u2net downloaded={downloaded} total={total} percent={percent:.1f}", flush=True)
            else:
                print(f"MODEL FETCH STATUS: step=3/3 rembg_u2net downloaded={downloaded}", flush=True)
            next_report = downloaded + 25 * 1024 * 1024
tmp_path.replace(model_path)
print(f"MODEL FETCH COMPLETE: step=3/3 rembg u2net ready path={model_path}", flush=True)
PY
}

export HF_HUB_DISABLE_PROGRESS_BARS="${HF_HUB_DISABLE_PROGRESS_BARS:-1}"
if [[ -n "${NYMPHS3D_HF_TOKEN:-}" ]]; then
  export HF_TOKEN="${NYMPHS3D_HF_TOKEN}"
  export HUGGING_FACE_HUB_TOKEN="${NYMPHS3D_HF_TOKEN}"
fi

mkdir -p "${NYMPHS3D_HF_CACHE_DIR}" "${U2NET_HOME}"

echo "trellis_model_repo=Aero-Ex/Trellis2-GGUF"
echo "trellis_support_repo=microsoft/TRELLIS.2-4B"
echo "trellis_gguf_quant=${TRELLIS_GGUF_QUANT}"
echo "download_all_quants=${download_all_quants}"
echo "hf_cache_dir=${NYMPHS3D_HF_CACHE_DIR}"
echo "u2net_dir=${U2NET_HOME}"
echo "model_fetch_plan=selected TRELLIS GGUF quant, required support checkpoint, and rembg u2net background-removal model"

if [[ "${download_all_quants}" == "true" ]]; then
  export TRELLIS_FETCH_ALL_QUANTS=1
else
  unset TRELLIS_FETCH_ALL_QUANTS
fi

(
  cd "${TRELLIS_INSTALL_ROOT}"
  "$(trellis_python)" - <<'PY'
import os
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path.cwd() / "scripts"))
from trellis_gguf_common import (
    GGUF_MODEL_REPO_ID,
    TRELLIS_SUPPORT_MODEL_REPO_ID,
    VALID_GGUF_QUANTS,
    ensure_required_support_models,
    resolve_gguf_model_root,
    resolve_gguf_quant,
)

cache_dir = os.environ.get("NYMPHS3D_HF_CACHE_DIR") or os.environ.get("HF_HUB_CACHE") or ""
raw_quant = (os.environ.get("TRELLIS_GGUF_QUANT") or "Q5_K_M").strip()
download_all = (os.environ.get("TRELLIS_FETCH_ALL_QUANTS") or "").lower() in {"1", "true", "yes", "on"}
quants = sorted(VALID_GGUF_QUANTS) if download_all else [resolve_gguf_quant(raw_quant)]
stop_event = threading.Event()

def cache_size_bytes(path: str) -> int:
    total = 0
    if not path or not os.path.isdir(path):
        return total
    for root, _, files in os.walk(path):
        for file_name in files:
            try:
                total += os.path.getsize(os.path.join(root, file_name))
            except OSError:
                pass
    return total

def format_bytes(size_bytes: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    value = float(size_bytes)
    unit = 0
    while value >= 1024 and unit < len(units) - 1:
        value /= 1024
        unit += 1
    return f"{value:.2f} {units[unit]}" if unit else f"{int(value)} {units[unit]}"

def heartbeat(start_size: int) -> None:
    last_size = start_size
    while not stop_event.wait(5):
        current_size = cache_size_bytes(cache_dir)
        delta = max(current_size - start_size, 0)
        recent = max(current_size - last_size, 0)
        print(
            "MODEL FETCH STATUS: step=1/3 repo="
            f"{GGUF_MODEL_REPO_ID} status=downloading cache_total={format_bytes(current_size)} "
            f"downloaded_this_step={format_bytes(delta)} recent_activity={format_bytes(recent)}/5s",
            flush=True,
        )
        last_size = current_size

start_size = cache_size_bytes(cache_dir)
print(
    "MODEL FETCH STARTED: step=1/3 TRELLIS GGUF quants "
    f"repo={GGUF_MODEL_REPO_ID} quants={','.join(quants)} cache_dir={cache_dir}",
    flush=True,
)
print(
    "MODEL FETCH NOTE: TRELLIS.2 GGUF files are large because each quant includes shape, refiner, texture, vision, encoder, and decoder components.",
    flush=True,
)
thread = threading.Thread(target=heartbeat, args=(start_size,), daemon=True)
thread.start()
try:
    for quant in quants:
        print(f"MODEL FETCH STATUS: step=1/3 downloading_quant={quant}", flush=True)
        root = resolve_gguf_model_root(local_files_only=False, quant=quant, include_texture=True)
        print(f"MODEL FETCH COMPLETE: step=1/3 quant={quant} root={root}", flush=True)
finally:
    stop_event.set()
    thread.join(timeout=1)

mid_size = cache_size_bytes(cache_dir)
print(
    "MODEL FETCH STARTED: step=2/3 support checkpoints "
    f"repo={TRELLIS_SUPPORT_MODEL_REPO_ID}",
    flush=True,
)
for config_file, model_file in ensure_required_support_models(local_files_only=False):
    print(f"MODEL FETCH COMPLETE: step=2/3 support_config={config_file}", flush=True)
    print(f"MODEL FETCH COMPLETE: step=2/3 support_model={model_file}", flush=True)

end_size = cache_size_bytes(cache_dir)
print(
    "MODEL FETCH COMPLETE: step=2/3 "
    f"cache_increase={format_bytes(max(end_size - start_size, 0))} "
    f"cache_total={format_bytes(end_size)}",
    flush=True,
)
PY
)

fetch_rembg_u2net

if [[ "${download_all_quants}" == "true" ]]; then
  echo "TRELLIS fetched all supported quants. Keeping current runtime preset at ${TRELLIS_GGUF_QUANT}."
else
  save_trellis_model_preset
  echo "TRELLIS model preset saved: quant=${TRELLIS_GGUF_QUANT} file=${TRELLIS_PRESET_FILE}"
fi
