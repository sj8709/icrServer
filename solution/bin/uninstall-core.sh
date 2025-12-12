#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# uninstall-core.sh — ICR 솔루션 제거 스크립트
#
# 기본 동작
#  - 서비스 중지
#  - Tomcat 디렉토리만 삭제 (심볼릭 링크 + 실제 디렉토리)
#  - 설정/로그/데이터/백업은 유지 (재설치 시 재사용)
#
# 옵션
#  --full        : INSTALL_BASE 전체 삭제 (설정/로그/데이터 포함)
#  --force       : 확인 프롬프트 스킵
#  --dry-run     : 삭제 대상만 출력 (실제 삭제 안 함)
#  -h, --help    : 도움말
#
# 삭제 대상 (기본)
#  - TOMCAT_HOME 심볼릭 링크
#  - 실제 Tomcat 디렉토리 (TOMCAT_DIST_NAME)
#
# 삭제 대상 (--full)
#  - INSTALL_BASE 전체
# -----------------------------------------------------------------------------

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"

# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

usage() {
  cat <<'EOF'
Usage:
  uninstall-core.sh [options]

Options:
  --full        INSTALL_BASE 전체 삭제 (설정/로그/데이터 포함)
  --force       확인 프롬프트 스킵
  --dry-run     삭제 대상만 출력 (실제 삭제 안 함)
  -h, --help    도움말

기본 동작:
  - Tomcat 중지
  - Tomcat 디렉토리만 삭제 (설정/로그/데이터 유지)

--full 옵션:
  - Tomcat 중지
  - INSTALL_BASE 전체 삭제
EOF
}

# ──────────────────────────────────────────────
# 옵션 파싱
# ──────────────────────────────────────────────
FULL_UNINSTALL="N"
FORCE="N"
DRY_RUN_LOCAL="N"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL_UNINSTALL="Y"; shift ;;
    --force) FORCE="Y"; shift ;;
    --dry-run) DRY_RUN_LOCAL="Y"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
  export DRY_RUN="Y"
fi

# ──────────────────────────────────────────────
# site.conf 로딩
# ──────────────────────────────────────────────
load_site_conf "${ROOT_DIR}"

# Tomcat 실제 디렉토리 경로 계산
TOMCAT_PARENT="$(dirname "${TOMCAT_HOME}")"
TOMCAT_ACTUAL="${TOMCAT_PARENT}/${TOMCAT_DIST_NAME}"

# ──────────────────────────────────────────────
# 삭제 대상 출력
# ──────────────────────────────────────────────
show_targets() {
  log "========================================"
  log "삭제 대상"
  log "========================================"

  if [[ "${FULL_UNINSTALL}" == "Y" ]]; then
    log "[FULL] INSTALL_BASE 전체: ${INSTALL_BASE}"
  else
    log "[기본] Tomcat 심볼릭 링크: ${TOMCAT_HOME}"
    log "[기본] Tomcat 실제 디렉토리: ${TOMCAT_ACTUAL}"
    log ""
    log "유지되는 디렉토리:"
    log "  - ${INSTALL_BASE}/config"
    log "  - ${INSTALL_BASE}/logs"
    log "  - ${INSTALL_BASE}/data"
    log "  - ${INSTALL_BASE}/backup"
  fi

  log "========================================"
}

# ──────────────────────────────────────────────
# 확인 프롬프트
# ──────────────────────────────────────────────
confirm_uninstall() {
  if [[ "${FORCE}" == "Y" ]]; then
    return 0
  fi

  if [[ "${DRY_RUN}" == "Y" ]]; then
    return 0
  fi

  echo ""
  if [[ "${FULL_UNINSTALL}" == "Y" ]]; then
    echo "경고: INSTALL_BASE 전체가 삭제됩니다!"
    echo "      설정, 로그, 데이터, 백업 모두 삭제됩니다."
  fi
  echo ""
  read -r -p "정말 삭제하시겠습니까? (y/N): " answer

  case "${answer}" in
    [yY]|[yY][eE][sS])
      return 0
      ;;
    *)
      log "취소되었습니다."
      exit 0
      ;;
  esac
}

# ──────────────────────────────────────────────
# Tomcat만 삭제 (기본)
# ──────────────────────────────────────────────
uninstall_tomcat_only() {
  log "Tomcat 디렉토리 삭제 시작"

  # 심볼릭 링크 삭제
  if [[ -L "${TOMCAT_HOME}" ]]; then
    log "심볼릭 링크 삭제: ${TOMCAT_HOME}"
    run "rm -f \"${TOMCAT_HOME}\""
  elif [[ -e "${TOMCAT_HOME}" ]]; then
    log "TOMCAT_HOME이 심볼릭 링크가 아닙니다: ${TOMCAT_HOME}"
    log "직접 디렉토리 삭제: ${TOMCAT_HOME}"
    run "rm -rf \"${TOMCAT_HOME}\""
  else
    log "TOMCAT_HOME 없음 (이미 삭제됨): ${TOMCAT_HOME}"
  fi

  # 실제 Tomcat 디렉토리 삭제
  if [[ -d "${TOMCAT_ACTUAL}" ]]; then
    log "Tomcat 디렉토리 삭제: ${TOMCAT_ACTUAL}"
    run "rm -rf \"${TOMCAT_ACTUAL}\""
  else
    log "Tomcat 디렉토리 없음 (이미 삭제됨): ${TOMCAT_ACTUAL}"
  fi

  log "Tomcat 삭제 완료"
}

# ──────────────────────────────────────────────
# 전체 삭제 (--full)
# ──────────────────────────────────────────────
uninstall_full() {
  log "INSTALL_BASE 전체 삭제 시작"

  if [[ -d "${INSTALL_BASE}" ]]; then
    log "전체 삭제: ${INSTALL_BASE}"
    run "rm -rf \"${INSTALL_BASE}\""
  else
    log "INSTALL_BASE 없음 (이미 삭제됨): ${INSTALL_BASE}"
  fi

  log "전체 삭제 완료"
}

# ──────────────────────────────────────────────
# 메인
# ──────────────────────────────────────────────
main() {
  log "ICR 솔루션 제거 시작"
  svc_diag

  show_targets
  confirm_uninstall

  # 서비스 중지 (Tomcat이 설치되지 않은 경우도 허용)
  log "서비스 중지 중..."
  if [[ -x "${TOMCAT_HOME}/bin/shutdown.sh" ]]; then
    svc_stop || true
  else
    log "shutdown.sh 없음 - 중지 생략 (미설치 상태)"
  fi

  # 삭제 실행
  if [[ "${FULL_UNINSTALL}" == "Y" ]]; then
    uninstall_full
  else
    uninstall_tomcat_only
  fi

  log "========================================"
  log "ICR 솔루션 제거 완료"
  if [[ "${FULL_UNINSTALL}" != "Y" ]]; then
    log ""
    log "유지된 디렉토리:"
    log "  - ${INSTALL_BASE}/config"
    log "  - ${INSTALL_BASE}/logs"
    log "  - ${INSTALL_BASE}/data"
    log "  - ${INSTALL_BASE}/backup"
    log ""
    log "전체 삭제가 필요하면: uninstall.sh --full"
  fi
  log "========================================"
}

main "$@"
