#!/usr/bin/env bash
#
# check.sh - 운영자용 종합 점검 스크립트
#
# 실행:
#   ./solution/bin/check.sh                    # 기본 점검
#   ./solution/bin/check.sh --with-health      # 헬스체크 포함
#   ./solution/bin/check.sh --tail 50          # 로그 50줄 출력
#
# 옵션:
#   --with-health           헬스체크 실행
#   --health-path <path>    헬스체크 경로 (기본: /icr/login)
#   --health-retry <N>      재시도 횟수 (기본: 3)
#   --health-interval <sec> 재시도 간격 (기본: 1초)
#   --tail <N>              catalina.out 마지막 N줄 출력
#   --dry-run               실제 실행 없이 명령만 출력
#   -h, --help              도움말
#
# 점검 항목:
#   1) 서비스 상태 (RUNNING/STOPPED)
#   2) Java 프로세스 정보
#   3) 포트 리슨 상태 (HTTP/HTTPS)
#   4) WAR 배포 파일 확인
#   5) 헬스체크 (선택)
#   6) 로그 tail (선택)
#
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"

# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

# ============================================================================
#  옵션 파싱
# ============================================================================

usage() {
    cat <<EOF
사용법:
  check.sh [옵션]

옵션:
  --with-health           헬스체크 실행 (기본: OFF)
  --health-path <path>    헬스체크 경로 (기본: /icr/login)
  --health-retry <N>      재시도 횟수 (기본: 3)
  --health-interval <sec> 재시도 간격 (기본: 1초)

  --tail <N>              catalina.out 마지막 N줄 출력 (기본: 0)
  --dry-run               실제 실행 없이 명령만 출력
  -h, --help              도움말

예시:
  check.sh                          # 기본 점검
  check.sh --with-health            # 헬스체크 포함
  check.sh --tail 100               # 로그 100줄 출력
  check.sh --with-health --tail 50  # 헬스체크 + 로그 50줄
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
        *) die "알 수 없는 옵션: $1 (--help 참조)" ;;
    esac
done

if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
    export DRY_RUN="Y"
fi

# ============================================================================
#  점검 시작
# ============================================================================

load_site_conf "${ROOT_DIR}"
svc_diag

echo "------------------------------------------------------------"
echo "1) 서비스 상태"
echo "------------------------------------------------------------"
if svc_status; then
    RUNNING="Y"
else
    RUNNING="N"
fi

echo "------------------------------------------------------------"
echo "2) Java 프로세스 정보"
echo "------------------------------------------------------------"
if [[ "${DRY_RUN}" == "Y" ]]; then
    log "[DRY-RUN] ps -ef | grep -F \"${TOMCAT_HOME}\" | grep -F java | grep -v grep"
else
    ps -ef | grep -F "${TOMCAT_HOME}" | grep -F java | grep -v grep || true
fi

echo "------------------------------------------------------------"
echo "3) 포트 리슨 상태"
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
    log "[경고] ss 명령어 없음. 포트 확인 생략."
fi

echo "------------------------------------------------------------"
echo "4) WAR 배포 파일"
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
        log "[경고] WAR 파일 없음: ${WAR_PATH}"
    fi
fi

echo "------------------------------------------------------------"
echo "5) 헬스체크 (선택)"
echo "------------------------------------------------------------"
if [[ "${WITH_HEALTH}" == "Y" ]]; then
    if [[ "${RUNNING}" != "Y" ]]; then
        log "헬스체크 생략: Tomcat 미실행 상태"
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
    log "헬스체크 생략. --with-health 옵션으로 활성화"
fi

echo "------------------------------------------------------------"
echo "6) 로그 tail (선택)"
echo "------------------------------------------------------------"
if [[ "${TAIL_N}" =~ ^[0-9]+$ ]] && (( TAIL_N > 0 )); then
    if [[ "${DRY_RUN}" == "Y" ]]; then
        log "[DRY-RUN] svc_tail ${TAIL_N}"
    else
        svc_tail "${TAIL_N}" || true
    fi
else
    log "로그 출력 생략. --tail <N> 옵션으로 활성화"
fi

echo "------------------------------------------------------------"
echo "점검 완료"
echo "------------------------------------------------------------"

exit 0
