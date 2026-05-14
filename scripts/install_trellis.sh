#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

ensure_module_submodules() {
  local eigen_dir="${MODULE_ROOT}/o-voxel/third_party/eigen"

  if [[ -f "${eigen_dir}/Eigen/Core" ]]; then
    return 0
  fi

  if [[ -d "${MODULE_ROOT}/.git" ]]; then
    echo "Initializing TRELLIS module submodules required for native builds"
    git -C "${MODULE_ROOT}" submodule update --init --recursive o-voxel/third_party/eigen
  fi

  if [[ ! -f "${eigen_dir}/Eigen/Core" ]]; then
    echo "Expected Eigen submodule is missing from ${eigen_dir}." >&2
    echo "Run git submodule update --init --recursive o-voxel/third_party/eigen in the module repo, then retry." >&2
    exit 1
  fi
}

sync_module_source() {
  if [[ "$(cd "${MODULE_ROOT}" && pwd)" == "$(mkdir -p "${TRELLIS_INSTALL_ROOT}" && cd "${TRELLIS_INSTALL_ROOT}" && pwd)" ]]; then
    return 0
  fi

  echo "Syncing TRELLIS module source into ${TRELLIS_INSTALL_ROOT}"
  mkdir -p "${TRELLIS_INSTALL_ROOT}"
  tar \
    --exclude='.git' \
    --exclude='.venv' \
    --exclude='.cache' \
    --exclude='.nymph-module-version' \
    --exclude='logs' \
    --exclude='outputs' \
    -cf - -C "${MODULE_ROOT}" . | tar -xf - -C "${TRELLIS_INSTALL_ROOT}"
}

sync_runtime_repo() {
  local name="$1"
  local repo_url="$2"
  local repo_ref="$3"
  local repo_path="$4"

  if [[ ! -d "${repo_path}/.git" ]]; then
    rm -rf "${repo_path}"
    echo "Cloning ${name} runtime package"
    GIT_TERMINAL_PROMPT=0 git clone --filter=blob:none --no-checkout "${repo_url}" "${repo_path}"
  fi

  echo "Syncing ${name} runtime package to ${repo_ref}"
  GIT_TERMINAL_PROMPT=0 git -C "${repo_path}" fetch --depth 1 origin "${repo_ref}"
  git -C "${repo_path}" checkout --detach FETCH_HEAD
  echo "${name}: active commit $(git -C "${repo_path}" rev-parse --short HEAD)"
}

install_trellis_gguf_runtime() {
  local package_dir="${TRELLIS_GGUF_RUNTIME_DIR}/ComfyUI-Trellis2-GGUF"
  local loader_dir="${TRELLIS_GGUF_RUNTIME_DIR}/ComfyUI-GGUF"
  local site_packages
  local loader_target

  echo "Installing TRELLIS.2 GGUF runtime dependencies"
  "$(trellis_pip)" install \
    gguf \
    rembg \
    onnxruntime \
    pymeshlab \
    meshlib \
    open3d \
    rectpack \
    sdnq \
    accelerate

  mkdir -p "${TRELLIS_GGUF_RUNTIME_DIR}"
  sync_runtime_repo "ComfyUI-Trellis2-GGUF" "${TRELLIS2_GGUF_REPO_URL}" "${TRELLIS2_GGUF_REPO_REF}" "${package_dir}"
  sync_runtime_repo "ComfyUI-GGUF" "${COMFYUI_GGUF_REPO_URL}" "${COMFYUI_GGUF_REPO_REF}" "${loader_dir}"

  site_packages="$(trellis_site_packages_dir)"
  if [[ ! -d "${package_dir}/trellis2_gguf" ]]; then
    echo "Expected trellis2_gguf package is missing from ${package_dir}" >&2
    exit 1
  fi
  if [[ ! -f "${loader_dir}/ops.py" || ! -f "${loader_dir}/dequant.py" || ! -f "${loader_dir}/loader.py" ]]; then
    echo "Expected ComfyUI-GGUF loader files are missing from ${loader_dir}" >&2
    exit 1
  fi

  rm -rf "${site_packages}/trellis2_gguf"
  cp -a "${package_dir}/trellis2_gguf" "${site_packages}/trellis2_gguf"

  loader_target="${site_packages}/ComfyUI-GGUF"
  mkdir -p "${loader_target}"
  cp -a "${loader_dir}/ops.py" "${loader_dir}/dequant.py" "${loader_dir}/loader.py" "${loader_target}/"

  "$(trellis_python)" - <<'PY'
import importlib

for module_name in ("trellis2_gguf", "gguf", "rembg", "open3d", "pymeshlab", "meshlib"):
    importlib.import_module(module_name)

print("TRELLIS.2 GGUF runtime imports available.")
PY
}

if [[ ! -d "${CUDA_HOME:-}" ]]; then
  echo "CUDA 13.0 was not found at ${CUDA_HOME:-/usr/local/cuda-13.0}" >&2
  exit 1
fi

if ! command -v python3.10 >/dev/null 2>&1; then
  echo "python3.10 is required for TRELLIS.2 GGUF." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required for TRELLIS.2 GGUF." >&2
  exit 1
fi

rm -f "${TRELLIS_INSTALL_ROOT}/.nymph-module-version"

ensure_module_submodules
sync_module_source
cd "${TRELLIS_INSTALL_ROOT}"

if [[ -d ".git" ]]; then
  echo "Initializing TRELLIS submodules required for native builds"
  git submodule update --init --recursive o-voxel/third_party/eigen
fi

if [[ ! -d ".venv" ]]; then
  echo "Creating Python 3.10 TRELLIS venv"
  python3.10 -m venv .venv
fi

if [[ ! -x "$(trellis_python)" ]]; then
  echo "TRELLIS venv was created, but python is missing." >&2
  exit 1
fi

export PATH="${TRELLIS_VENV_DIR}/bin:${PATH}"

"$(trellis_python)" --version
"$(trellis_pip)" install --upgrade pip setuptools wheel ninja

if ! "$(trellis_python)" -c 'import torch, torchvision' >/dev/null 2>&1; then
  echo "Installing PyTorch for TRELLIS.2 runtime"
  "$(trellis_pip)" install torch==2.11.0 torchvision torchaudio --index-url "${TRELLIS_TORCH_INDEX_URL}"
fi

echo "Installing TRELLIS Python dependencies"
"$(trellis_pip)" install \
  imageio \
  imageio-ffmpeg \
  tqdm \
  easydict \
  opencv-python-headless \
  trimesh \
  transformers \
  gradio==6.0.1 \
  tensorboard \
  pandas \
  lpips \
  zstandard \
  kornia \
  timm \
  psutil \
  plyfile

"$(trellis_pip)" install "git+https://github.com/EasternJournalist/utils3d.git@${UTILS3D_REF}"

if [[ -n "${TRELLIS_CUDA_ARCH_LIST:-${NYMPHS3D_TRELLIS_CUDA_ARCH_LIST:-}}" ]]; then
  export TORCH_CUDA_ARCH_LIST="${TRELLIS_CUDA_ARCH_LIST:-${NYMPHS3D_TRELLIS_CUDA_ARCH_LIST:-}}"
elif command -v nvidia-smi >/dev/null 2>&1; then
  detected_cc="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n 1 | tr -d '[:space:]')"
  if [[ "${detected_cc}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    export TORCH_CUDA_ARCH_LIST="${detected_cc}"
  fi
fi

if ! "$(trellis_python)" -c 'import flash_attn' >/dev/null 2>&1; then
  echo "Installing required flash-attn for TRELLIS.2"
  MAX_JOBS="${TRELLIS_FLASH_ATTN_MAX_JOBS:-1}" \
  CMAKE_BUILD_PARALLEL_LEVEL="${TRELLIS_FLASH_ATTN_MAX_JOBS:-1}" \
  MAKEFLAGS="-j${TRELLIS_FLASH_ATTN_MAX_JOBS:-1}" \
  NINJAFLAGS="-j${TRELLIS_FLASH_ATTN_MAX_JOBS:-1}" \
  NVCC_THREADS="${TRELLIS_FLASH_ATTN_NVCC_THREADS:-1}" \
  "$(trellis_pip)" install --no-build-isolation flash-attn
fi

echo "Building TRELLIS native runtime extensions"
"$(trellis_pip)" install --no-build-isolation \
  "git+https://github.com/JeffreyXiang/CuMesh.git@${TRELLIS_CUMESH_REF}" \
  "git+https://github.com/JeffreyXiang/FlexGEMM.git@${TRELLIS_FLEXGEMM_REF}" \
  "git+https://github.com/NVlabs/nvdiffrast.git@${TRELLIS_NVDIFFRAST_REF}"

"$(trellis_pip)" install --no-build-isolation --no-deps ./o-voxel

install_trellis_gguf_runtime

"$(trellis_python)" scripts/api_server_trellis_gguf.py --help >/dev/null

module_version="$(python3 - "${MODULE_ROOT}/nymph.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

print(str(manifest.get("version", "unknown")).strip() or "unknown")
PY
)"
printf '%s\n' "${module_version}" > "${TRELLIS_INSTALL_ROOT}/.nymph-module-version"
echo "installed_module_version=${module_version}"
echo "TRELLIS.2 GGUF install complete."
