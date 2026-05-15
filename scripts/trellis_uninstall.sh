#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

PURGE=0
DATA_ONLY=0
DRY_RUN=0
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --data-only) DATA_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: trellis_uninstall.sh [--dry-run] [--yes] [--purge] [--data-only]

Default uninstall removes the TRELLIS runtime install but preserves outputs and logs.
--purge removes the whole install root. Shared NymphsData outputs, logs, model
cache, and config are preserved.
--data-only deletes TRELLIS outputs, logs, config, rembg model data, and legacy
install-root data while keeping the runtime.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${PURGE}" -eq 1 && "${DATA_ONLY}" -eq 1 ]]; then
  echo "Choose only one of --purge or --data-only." >&2
  exit 2
fi

echo "TRELLIS.2 uninstall plan"
echo "install_root=${TRELLIS_INSTALL_ROOT}"
if [[ "${DATA_ONLY}" -eq 1 ]]; then
  echo "mode=data-only"
  echo "delete=${TRELLIS_OUTPUT_DIR}"
  echo "delete=${TRELLIS_LOG_DIR}"
  echo "delete=${TRELLIS_CONFIG_DIR}"
  echo "delete=${U2NET_HOME}"
  echo "delete=${TRELLIS_INSTALL_ROOT}/outputs"
  echo "delete=${TRELLIS_INSTALL_ROOT}/logs"
  echo "preserve=${TRELLIS_INSTALL_ROOT}"
  echo "preserve=${NYMPHS3D_HF_CACHE_DIR}"
elif [[ "${PURGE}" -eq 1 ]]; then
  echo "mode=purge"
  echo "delete=${TRELLIS_INSTALL_ROOT}"
else
  echo "mode=uninstall"
  echo "delete=runtime files, source files, venvs inside ${TRELLIS_INSTALL_ROOT}"
  echo "preserve=${TRELLIS_OUTPUT_DIR}"
  echo "preserve=${TRELLIS_LOG_DIR}"
  echo "preserve=${TRELLIS_CONFIG_DIR}"
  echo "preserve=${NYMPHS3D_HF_CACHE_DIR}"
  echo "preserve=${U2NET_HOME}"
  echo "preserve_legacy=${TRELLIS_INSTALL_ROOT}/outputs"
  echo "preserve_legacy=${TRELLIS_INSTALL_ROOT}/logs"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  exit 0
fi

if [[ "${YES}" -ne 1 ]]; then
  echo "Refusing to delete without --yes. Run with --dry-run first to preview." >&2
  exit 2
fi

"${SCRIPT_DIR}/trellis_stop.sh" || true

if [[ ! -d "${TRELLIS_INSTALL_ROOT}" ]]; then
  if [[ "${DATA_ONLY}" -ne 1 ]]; then
    echo "TRELLIS.2 is already uninstalled."
    exit 0
  fi
fi

if [[ "${DATA_ONLY}" -eq 1 ]]; then
  rm -rf \
    "${TRELLIS_OUTPUT_DIR}" \
    "${TRELLIS_LOG_DIR}" \
    "${TRELLIS_CONFIG_DIR}" \
    "${U2NET_HOME}" \
    "${TRELLIS_INSTALL_ROOT}/outputs" \
    "${TRELLIS_INSTALL_ROOT}/logs"
elif [[ "${PURGE}" -eq 1 ]]; then
  rm -rf "${TRELLIS_INSTALL_ROOT}"
else
  rm -f "${TRELLIS_INSTALL_ROOT}/.nymph-module-version"
  find "${TRELLIS_INSTALL_ROOT}" -mindepth 1 \
    \( -name outputs -o -name logs \) -prune -o \
    -exec rm -rf {} +
fi

if [[ "${DATA_ONLY}" -eq 1 ]]; then
  echo "TRELLIS.2 data deleted."
else
  echo "TRELLIS.2 uninstalled."
fi
