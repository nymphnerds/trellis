#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_trellis_common.sh"

mkdir -p "${TRELLIS_OUTPUT_DIR}"
echo "directory=${TRELLIS_OUTPUT_DIR}"
