#!/usr/bin/env bash
#
# uninstall.sh - ICR 솔루션 제거 (래퍼)
#
# 실행:
#   ./uninstall.sh                 # 기본 제거 (Tomcat만, 설정 유지)
#   ./uninstall.sh --full          # 전체 삭제 (설정/로그/데이터 포함)
#   ./uninstall.sh --dry-run       # 삭제 대상 미리보기
#
# 옵션:
#   --full        INSTALL_BASE 전체 삭제 (설정/로그/데이터 포함)
#   --force       확인 프롬프트 스킵
#   --dry-run     삭제 대상만 출력 (실제 삭제 안 함)
#   -h, --help    도움말
#
# 이 스크립트는 solution/bin/uninstall-core.sh를 호출하는 래퍼입니다.
# 실제 제거 로직은 uninstall-core.sh에 구현되어 있습니다.
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CORE_SCRIPT="${BASE_DIR}/solution/bin/uninstall-core.sh"

if [[ ! -x "${CORE_SCRIPT}" ]]; then
    echo "[ERROR] 코어 스크립트 없음 또는 실행 불가: ${CORE_SCRIPT}" >&2
    exit 1
fi

exec "${CORE_SCRIPT}" "$@"
