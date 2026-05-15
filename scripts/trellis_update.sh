#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

if [[ ! -f "${TRELLIS_INSTALL_ROOT}/.nymph-module-version" ]]; then
  echo "TRELLIS.2 is not installed yet. Use Install first." >&2
  exit 2
fi

echo "Syncing TRELLIS.2 module wrappers into ${TRELLIS_INSTALL_ROOT}"
mkdir -p "${TRELLIS_INSTALL_ROOT}"
tar \
  --exclude='.git' \
  --exclude='.venv' \
  --exclude='.cache' \
  --exclude='.nymph-module-version' \
  --exclude='logs' \
  --exclude='outputs' \
  -cf - -C "${MODULE_ROOT}" . | tar -xf - -C "${TRELLIS_INSTALL_ROOT}"

module_version="$(python3 - "${MODULE_ROOT}/nymph.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

print(str(manifest.get("version", "unknown")).strip() or "unknown")
PY
)"
printf '%s\n' "${module_version}" > "${TRELLIS_INSTALL_ROOT}/.nymph-module-version"

echo "TRELLIS.2 module wrappers updated."
echo "installed_version=${module_version}"
