#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

PURGE=0
DRY_RUN=0
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: trellis_uninstall.sh [--dry-run] [--yes] [--purge]

Default uninstall removes the TRELLIS runtime install but preserves outputs and logs.
--purge removes the whole install root, including outputs and logs.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

echo "TRELLIS.2 uninstall plan"
echo "install_root=${TRELLIS_INSTALL_ROOT}"
if [[ "${PURGE}" -eq 1 ]]; then
  echo "mode=purge"
  echo "delete=${TRELLIS_INSTALL_ROOT}"
else
  echo "mode=uninstall"
  echo "delete=runtime files, source files, venvs inside ${TRELLIS_INSTALL_ROOT}"
  echo "preserve=${TRELLIS_INSTALL_ROOT}/outputs"
  echo "preserve=${TRELLIS_INSTALL_ROOT}/logs"
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
  echo "TRELLIS.2 is already uninstalled."
  exit 0
fi

if [[ "${PURGE}" -eq 1 ]]; then
  rm -rf "${TRELLIS_INSTALL_ROOT}"
else
  find "${TRELLIS_INSTALL_ROOT}" -mindepth 1 \
    ! -name outputs \
    ! -name logs \
    -exec rm -rf {} +
fi

echo "TRELLIS.2 uninstalled."
