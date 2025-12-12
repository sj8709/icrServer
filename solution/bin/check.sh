#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# check.sh — 운영자용 종합 점검 스크립트
#
# 하는 일
#  1) site.conf 로드 + 핵심 설정 출력
#  2) Tomcat RUNNING/STOPPED 확인
#  3) java 프로세스(해당 TOMCAT_HOME 기준) 요약 출력
#  4) 포트 리슨 상태(HTTP/HTTPS) 확인
#  5) 배포 WAR 파일 상태 확인(appBase/icr.war)
#  6) (옵션) health.sh 호출로 서비스 응답 확인
#  7) (옵션) catalina.out tail 출력
#
# 옵션
#  --with-health        : health.sh 실행(기본 /icr/login)
#  --health-path <p>    : health.sh --path (기본 /icr/login)
#  --health-retry <N>   : health.sh --retry (기본 3)
#  --health-interval <s>: health.sh --interval (기본 1)
#
#  --tail <N>           : catalina.out tail N줄 출력(기본 0=안함)
#  --dry-run            : DRY RUN
# -----------------------------------------------------------------------------

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"

# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

usage() {
  cat <<'EOF'
Usage:
  check.sh [options]

Options:
  --with-health           run health.sh (default: OFF)
  --health-path <path>    default /icr/login
  --health-retry <N>      default 3
  --health-interval <sec> default 1

  --tail <N>              tail catalina.out N lines (default 0)
  --dry-run               dry run
  -h, --help              help
EOF
}

WITH_HEALTH="N"
HEALTH_PATH="/icr/login"
HEALTH_RETRY=3
HEALTH_INTERVAL=1
TAIL_N=0
DRY_RUN_LOCAL="N"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-health) WITH_HEALTH="Y"; shift ;;
    --health-path) HEALTH_PATH="${2:-}"; shift 2 ;;
    --health-retry) HEALTH_RETRY="${2:-}"; shift 2 ;;
    --health-interval) HEALTH_INTERVAL="${2:-}"; shift 2 ;;
    --tail) TAIL_N="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN_LOCAL="Y"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
  export DRY_RUN="Y"
fi

load_site_conf "${ROOT_DIR}"
svc_diag

echo "------------------------------------------------------------"
echo "1) Service status"
echo "------------------------------------------------------------"
if svc_status; then
  RUNNING="Y"
else
  RUNNING="N"
fi

echo "------------------------------------------------------------"
echo "2) Process (java) summary"
echo "------------------------------------------------------------"
if [[ "${DRY_RUN}" == "Y" ]]; then
  log "[DRY-RUN] ps -ef | grep -F \"${TOMCAT_HOME}\" | grep -F java | grep -v grep"
else
  ps -ef | grep -F "${TOMCAT_HOME}" | grep -F java | grep -v grep || true
fi

echo "------------------------------------------------------------"
echo "3) Port listen check"
echo "------------------------------------------------------------"
WAS_HTTP_PORT="${WAS_HTTP_PORT:-28080}"
WAS_HTTPS_PORT="${WAS_HTTPS_PORT:-28443}"
WAS_ENABLE_HTTPS="${WAS_ENABLE_HTTPS:-N}"

if command -v ss >/dev/null 2>&1; then
  if [[ "${DRY_RUN}" == "Y" ]]; then
    log "[DRY-RUN] ss -lntp | grep -E \":(${WAS_HTTP_PORT}|${WAS_HTTPS_PORT})\\b\" || true"
  else
    ss -lntp | grep -E ":(${WAS_HTTP_PORT}|${WAS_HTTPS_PORT})\b" || true
  fi
else
  log "WARN: ss not found. Skip port check."
fi

echo "------------------------------------------------------------"
echo "4) WAR deploy file"
echo "------------------------------------------------------------"
APP_BASE_DIR="${TOMCAT_HOME}/${WAS_APP_BASE}"
WAR_PATH="${APP_BASE_DIR}/icr.war"

echo "APP_BASE_DIR = ${APP_BASE_DIR}"
echo "WAR_PATH     = ${WAR_PATH}"

if [[ "${DRY_RUN}" == "Y" ]]; then
  log "[DRY-RUN] ls -al \"${WAR_PATH}\""
else
  if [[ -f "${WAR_PATH}" ]]; then
    ls -al "${WAR_PATH}"
  else
    log "WARN: WAR not found: ${WAR_PATH}"
  fi
fi

echo "------------------------------------------------------------"
echo "5) Optional health check"
echo "------------------------------------------------------------"
if [[ "${WITH_HEALTH}" == "Y" ]]; then
  if [[ "${RUNNING}" != "Y" ]]; then
    log "Skip health: Tomcat is not running."
  else
    HEALTH_CMD=(
      "${ROOT_DIR}/solution/bin/health.sh"
      --path "${HEALTH_PATH}"
      --retry "${HEALTH_RETRY}"
      --interval "${HEALTH_INTERVAL}"
    )

    if [[ "${DRY_RUN}" == "Y" ]]; then
      log "[DRY-RUN] ${HEALTH_CMD[*]}"
    else
      "${HEALTH_CMD[@]}"
    fi
  fi
else
  log "Health check skipped. Use --with-health to enable."
fi

echo "------------------------------------------------------------"
echo "6) Optional catalina.out tail"
echo "------------------------------------------------------------"
if [[ "${TAIL_N}" =~ ^[0-9]+$ ]] && (( TAIL_N > 0 )); then
  if [[ "${DRY_RUN}" == "Y" ]]; then
    log "[DRY-RUN] svc_tail ${TAIL_N}"
  else
    svc_tail "${TAIL_N}" || true
  fi
else
  log "Log tail skipped. Use --tail <N> to enable."
fi

echo "------------------------------------------------------------"
echo "Done."
echo "------------------------------------------------------------"

# 운영자 편의: check 자체는 상태만 보여주고 exit 0 유지
exit 0

