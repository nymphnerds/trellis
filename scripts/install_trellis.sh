#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

has_apt_candidate() {
  local package_name="$1"
  local candidate
  candidate="$(apt-cache policy "${package_name}" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

ensure_system_dependencies() {
  local need_apt=0

  for command_name in git curl cmake pkg-config; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      need_apt=1
    fi
  done

  if ! command -v python3.10 >/dev/null 2>&1 ||
     ! python3.10 - <<'PY' >/dev/null 2>&1 ||
import venv
PY
     { ! command -v dpkg >/dev/null 2>&1 || ! dpkg -s python3.10-dev >/dev/null 2>&1; }; then
    need_apt=1
  fi

  if [[ "${need_apt}" -ne 1 ]]; then
    return 0
  fi

  echo "Installing TRELLIS.2 system dependencies."

  if ! command -v sudo >/dev/null 2>&1 ||
     ! command -v apt-cache >/dev/null 2>&1; then
    echo "Required system packages are missing and automatic apt installation is not available." >&2
    echo "Install python3.10, python3.10-venv, python3.10-dev, git, curl, cmake, pkg-config, and build-essential, then retry." >&2
    exit 1
  fi

  sudo apt update
  sudo apt install -y \
    ca-certificates \
    cmake \
    git \
    wget \
    curl \
    unzip \
    build-essential \
    pkg-config \
    software-properties-common \
    python3 \
    python3-venv \
    python3-pip \
    libegl1-mesa-dev \
    libgl1 \
    libglib2.0-0 \
    ccache

  if ! has_apt_candidate python3.10 || ! has_apt_candidate python3.10-venv || ! has_apt_candidate python3.10-dev; then
    echo "Python 3.10 packages are not available in current apt sources. Adding deadsnakes PPA..."
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt update
  fi

  sudo apt install -y \
    python3.10 \
    python3.10-venv \
    python3.10-dev

  if apt-cache show python3.10-distutils >/dev/null 2>&1; then
    sudo apt install -y python3.10-distutils
  fi
}

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

map_flash_attn_cuda_arch() {
  local compute_cap="$1"
  local major="${compute_cap%%.*}"

  case "${major}" in
    8)
      echo "80"
      ;;
    9)
      echo "90"
      ;;
    10)
      echo "100"
      ;;
    11)
      echo "110"
      ;;
    12)
      echo "120"
      ;;
  esac
}

resolve_flash_attn_cuda_archs() {
  local detected_caps=""
  local compute_cap=""
  local arch=""

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    return 0
  fi

  detected_caps="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null || true)"
  while IFS= read -r compute_cap; do
    compute_cap="$(tr -d '[:space:]' <<< "${compute_cap}")"
    if [[ ! "${compute_cap}" =~ ^[0-9]+\.[0-9]+$ ]]; then
      continue
    fi

    arch="$(map_flash_attn_cuda_arch "${compute_cap}")"
    if [[ -z "${arch}" ]]; then
      continue
    fi

    echo "${arch}"
    return 0
  done <<< "${detected_caps}"
}

normalize_flash_attn_cuda_archs() {
  local raw="$1"
  local arch=""
  local selected_arch=""

  raw="$(tr ', ' ';;' <<< "${raw}")"
  while IFS= read -r arch; do
    arch="$(tr -d '[:space:]' <<< "${arch}")"
    arch="${arch,,}"
    arch="${arch#sm}"
    [[ -z "${arch}" ]] && continue

    case "${arch}" in
      80|90|100|110|120)
        ;;
      *)
        echo "Invalid TRELLIS_FLASH_ATTN_CUDA_ARCHS value: ${arch}" >&2
        echo "Use auto or one of: sm80, sm90, sm100, sm110, sm120." >&2
        return 1
        ;;
    esac

    if [[ -n "${selected_arch}" && "${selected_arch}" != "${arch}" ]]; then
      echo "TRELLIS_FLASH_ATTN_CUDA_ARCHS accepts one target arch for this install, not '${raw}'." >&2
      echo "Choose one GPU target in the Manager dropdown so flash-attn does not compile multiple arch families." >&2
      return 1
    fi

    selected_arch="${arch}"
  done < <(tr ';' '\n' <<< "${raw}")

  echo "${selected_arch}"
}

install_flash_attn() {
  local flash_attn_jobs="${TRELLIS_FLASH_ATTN_MAX_JOBS:-${NYMPHS3D_TRELLIS_FLASH_ATTN_MAX_JOBS:-4}}"
  local flash_attn_nvcc_threads="${TRELLIS_FLASH_ATTN_NVCC_THREADS:-${NYMPHS3D_TRELLIS_FLASH_ATTN_NVCC_THREADS:-2}}"
  local requested_flash_attn_archs="${TRELLIS_FLASH_ATTN_CUDA_ARCHS:-${NYMPHS3D_TRELLIS_FLASH_ATTN_CUDA_ARCHS:-${FLASH_ATTN_CUDA_ARCHS:-}}}"
  local flash_attn_archs=""
  local -a flash_attn_env=()

  if "$(trellis_python)" -c 'import flash_attn' >/dev/null 2>&1; then
    echo "flash-attn already available."
    return 0
  fi

  echo "Installing required flash-attn for TRELLIS.2 using the official pip path."
  echo "flash-attn install command: pip install flash-attn --no-build-isolation"

  if [[ -n "${requested_flash_attn_archs}" &&
        "${requested_flash_attn_archs,,}" != "auto" ]]; then
    flash_attn_archs="$(normalize_flash_attn_cuda_archs "${requested_flash_attn_archs}")"
  fi
  if [[ -z "${flash_attn_archs}" ]]; then
    flash_attn_archs="$(resolve_flash_attn_cuda_archs)"
  fi
  if [[ -n "${flash_attn_archs}" ]]; then
    if [[ -n "${requested_flash_attn_archs}" && "${requested_flash_attn_archs,,}" != "auto" ]]; then
      echo "Using explicit flash-attn CUDA arch list: ${flash_attn_archs}"
    else
      echo "Auto-selected flash-attn CUDA arch list: ${flash_attn_archs}"
    fi
    echo "Set TRELLIS_FLASH_ATTN_CUDA_ARCHS to override this GPU arch selection."
    flash_attn_env+=("FLASH_ATTN_CUDA_ARCHS=${flash_attn_archs}")
  else
    echo "Could not select one flash-attn CUDA arch target." >&2
    echo "Choose a GPU target manually in the Manager so flash-attn does not compile its broad package default arch list." >&2
    exit 1
  fi

  "$(trellis_pip)" install packaging psutil ninja
  if ! "$(trellis_python)" - <<'PY' >/dev/null 2>&1
import subprocess
import sys

completed = subprocess.run(["ninja", "--version"])
sys.exit(completed.returncode)
PY
  then
    echo "ninja is installed but did not run cleanly. Reinstalling ninja before flash-attn."
    "$(trellis_pip)" uninstall -y ninja || true
    "$(trellis_pip)" install ninja
  fi

  if [[ ! "${flash_attn_jobs}" =~ ^[0-9]+$ || "${flash_attn_jobs}" -lt 1 ]]; then
    echo "Invalid TRELLIS_FLASH_ATTN_MAX_JOBS value: ${flash_attn_jobs}" >&2
    exit 1
  fi
  echo "Limiting flash-attn build parallelism with MAX_JOBS=${flash_attn_jobs}."
  echo "Set TRELLIS_FLASH_ATTN_MAX_JOBS to override this cap."
  flash_attn_env+=("MAX_JOBS=${flash_attn_jobs}")
  flash_attn_env+=("CMAKE_BUILD_PARALLEL_LEVEL=${flash_attn_jobs}")
  flash_attn_env+=("MAKEFLAGS=-j${flash_attn_jobs}")
  flash_attn_env+=("NINJAFLAGS=-j${flash_attn_jobs}")

  if [[ -n "${flash_attn_nvcc_threads}" ]]; then
    if [[ ! "${flash_attn_nvcc_threads}" =~ ^[0-9]+$ || "${flash_attn_nvcc_threads}" -lt 1 ]]; then
      echo "Invalid TRELLIS_FLASH_ATTN_NVCC_THREADS value: ${flash_attn_nvcc_threads}" >&2
      exit 1
    fi
    echo "Using NVCC_THREADS=${flash_attn_nvcc_threads} for flash-attn."
    flash_attn_env+=("NVCC_THREADS=${flash_attn_nvcc_threads}")
  fi

  env "${flash_attn_env[@]}" "$(trellis_pip)" install --no-build-isolation flash-attn
}

ensure_system_dependencies

if [[ ! -d "${CUDA_HOME:-}" ]]; then
  echo "CUDA 13.0 was not found at ${CUDA_HOME:-/usr/local/cuda-13.0}" >&2
  echo "Install CUDA Toolkit 13.0 for WSL, then retry TRELLIS.2 installation." >&2
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

install_flash_attn

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
