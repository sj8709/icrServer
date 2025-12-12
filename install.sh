#!/usr/bin/env bash
#
# install.sh - ICR 솔루션 설치 (래퍼)
#
# 실행:
#   ./install.sh                       # 기본 설치
#   ICR_FORCE_REGEN=Y ./install.sh     # 설정 파일 강제 재생성
#
# 환경변수:
#   ICR_FORCE_REGEN=Y    기존 설정 파일이 있어도 템플릿에서 재생성
#
# 이 스크립트는 solution/bin/install-core.sh를 호출하는 래퍼입니다.
# 실제 설치 로직은 install-core.sh에 구현되어 있습니다.
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CORE_SCRIPT="${BASE_DIR}/solution/bin/install-core.sh"

if [[ ! -x "${CORE_SCRIPT}" ]]; then
    echo "[ERROR] 코어 스크립트 없음 또는 실행 불가: ${CORE_SCRIPT}" >&2
    exit 1
fi

exec "${CORE_SCRIPT}" "$@"
