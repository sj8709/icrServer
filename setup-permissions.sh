#!/usr/bin/env bash
#
# setup-permissions.sh - 스크립트 실행 권한 복구
#
# 용도:
#   Windows에서 작업 후 Linux로 복사 시 실행 권한이 사라지는 경우
#   이 스크립트를 1회 실행하여 권한을 복구합니다.
#
# 실행:
#   chmod +x setup-permissions.sh && ./setup-permissions.sh
#   bash setup-permissions.sh
#
# 권한 설정 대상:
#   - 루트: install.sh, uninstall.sh 등
#   - solution/bin/*.sh
#   - solution/modules/*.sh
#
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

echo "[setup-permissions] 스크립트 실행 권한 설정 시작"

# 루트 스크립트
chmod +x "${BASE_DIR}/"*.sh 2>/dev/null || true
echo "  - 루트: ${BASE_DIR}/*.sh"

# solution/bin/*.sh
if [[ -d "${BASE_DIR}/solution/bin" ]]; then
    chmod +x "${BASE_DIR}/solution/bin/"*.sh 2>/dev/null || true
    echo "  - solution/bin/*.sh"
fi

# solution/modules/*.sh
if [[ -d "${BASE_DIR}/solution/modules" ]]; then
    chmod +x "${BASE_DIR}/solution/modules/"*.sh 2>/dev/null || true
    echo "  - solution/modules/*.sh"
fi

echo "[setup-permissions] 완료"
echo ""
echo "이제 ./install.sh 또는 ./uninstall.sh 를 실행할 수 있습니다."
