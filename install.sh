#!/usr/bin/env bash
#
# ICR 솔루션 - 최상위 설치 진입점 (래퍼)
# 사용자는 항상 이 스크립트만 실행하면 됨.
#
#   ./install.sh
#   ./install.sh 옵션...
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CORE_SCRIPT="${BASE_DIR}/solution/bin/install-core.sh"

if [[ ! -x "${CORE_SCRIPT}" ]]; then
  echo "[install.sh][ERROR] core script not found or not executable: ${CORE_SCRIPT}" >&2
  exit 1
fi

exec "${CORE_SCRIPT}" "$@"

