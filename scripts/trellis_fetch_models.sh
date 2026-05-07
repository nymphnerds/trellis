#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

if [[ ! -x "$(trellis_python)" ]]; then
  echo "TRELLIS.2 runtime is missing. Run scripts/install_trellis.sh first." >&2
  exit 1
fi

(
  cd "${TRELLIS_INSTALL_ROOT}"
  "$(trellis_python)" - <<'PY'
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path.cwd() / "scripts"))
from trellis_gguf_common import (
    DEFAULT_GGUF_QUANT,
    TRELLIS_SUPPORT_MODEL_REPO_ID,
    VALID_GGUF_QUANTS,
    ensure_required_support_models,
    resolve_gguf_model_root,
)

raw_quant = (os.getenv("TRELLIS_GGUF_QUANT") or DEFAULT_GGUF_QUANT).strip()
quants = sorted(VALID_GGUF_QUANTS) if raw_quant.lower() == "all" else [raw_quant]

for quant in quants:
    print(f"Prefetching TRELLIS GGUF quant {quant}", flush=True)
    root = resolve_gguf_model_root(local_files_only=False, quant=quant, include_texture=True)
    print(f"TRELLIS GGUF quant {quant} ready: {root}", flush=True)

print(f"Prefetching TRELLIS GGUF support checkpoints from {TRELLIS_SUPPORT_MODEL_REPO_ID}", flush=True)
for config_file, model_file in ensure_required_support_models(local_files_only=False):
    print(f"Support checkpoint ready: {config_file}", flush=True)
    print(f"Support checkpoint ready: {model_file}", flush=True)
PY
)
