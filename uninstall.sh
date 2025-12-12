#!/usr/bin/env bash
#
# ICR 솔루션 - 제거 스크립트 래퍼
# 사용자는 항상 이 스크립트만 실행하면 됨.
#
#   ./uninstall.sh              # Tomcat만 삭제 (설정/데이터 유지)
#   ./uninstall.sh --full       # 전체 삭제
#   ./uninstall.sh --dry-run    # 삭제 대상만 확인
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CORE_SCRIPT="${BASE_DIR}/solution/bin/uninstall-core.sh"

if [[ ! -x "${CORE_SCRIPT}" ]]; then
  echo "[uninstall.sh][ERROR] core script not found or not executable: ${CORE_SCRIPT}" >&2
  exit 1
fi

exec "${CORE_SCRIPT}" "$@"
