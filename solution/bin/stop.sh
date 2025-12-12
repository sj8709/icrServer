#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# stop.sh — Tomcat 중지 엔트리 스크립트
#
# 역할:
#   - 사람이 직접 실행하는 중지 명령
#   - 실제 로직은 service_control.sh에 위임
#
# 특징:
#   - systemd 미사용
#   - startup/shutdown 기반
#   - DRY_RUN 지원
# -----------------------------------------------------------------------------

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"

# 공통 서비스 제어 모듈 로딩
# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

# site.conf 로딩
load_site_conf "${ROOT_DIR}"

# 진단 출력 (선택이지만 운영 시 매우 유용)
svc_diag

# Tomcat 중지
svc_stop

