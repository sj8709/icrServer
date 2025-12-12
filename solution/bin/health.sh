#!/usr/bin/env bash
#
# health.sh - HTTP 헬스체크 스크립트
#
# 실행:
#   ./solution/bin/health.sh                    # 기본 체크
#   ./solution/bin/health.sh --path /api/ping   # 경로 지정
#   ./solution/bin/health.sh --retry 10         # 10회 재시도
#   ./solution/bin/health.sh --verbose          # 실패 시 상세 출력
#
# 옵션:
#   --path <path>       체크 경로 (기본: /icr/login)
#   --timeout <sec>     curl 타임아웃 (기본: 5초)
#   --retry <N>         재시도 횟수 (기본: 3)
#   --interval <sec>    재시도 간격 (기본: 1초)
#   --verbose           실패 시 응답 헤더 출력 (000 제외)
#   --dry-run           실제 실행 없이 명령만 출력
#   -h, --help          도움말
#
# 성공 판정:
#   HTTP 200, 30x, 401, 403
#
# WARMING UP:
#   HTTP 코드 000 (응답 없음) -> 아직 앱 기동 중
#   FAIL 대신 "WARMING UP" 출력 후 재시도 계속
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
  health.sh [옵션]

옵션:
  --path <path>       체크 경로 (기본: /icr/login)
  --timeout <sec>     curl 타임아웃 (기본: 5초)
  --retry <N>         재시도 횟수 (기본: 3)
  --interval <sec>    재시도 간격 (기본: 1초)
  --verbose           실패 시 응답 헤더 출력 (000 제외)
  --dry-run           실제 실행 없이 명령만 출력
  -h, --help          도움말

예시:
  health.sh                      # 기본 체크
  health.sh --path /api/health   # 경로 지정
  health.sh --retry 10           # 10회 재시도
  health.sh --verbose            # 상세 출력
EOF
}

CHECK_PATH="/icr/login"
TIMEOUT_SEC=5
RETRY_N=3
INTERVAL_SEC=1
VERBOSE="N"
DRY_RUN_LOCAL="N"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) CHECK_PATH="${2:-}"; shift 2 ;;
        --timeout) TIMEOUT_SEC="${2:-}"; shift 2 ;;
        --retry) RETRY_N="${2:-}"; shift 2 ;;
        --interval) INTERVAL_SEC="${2:-}"; shift 2 ;;
        --verbose) VERBOSE="Y"; shift ;;
        --dry-run) DRY_RUN_LOCAL="Y"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "알 수 없는 옵션: $1 (--help 참조)" ;;
    esac
done

if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
    export DRY_RUN="Y"
fi

# ============================================================================
#  헬스체크 실행
# ============================================================================

load_site_conf "${ROOT_DIR}"
svc_diag

if ! is_running; then
    log "헬스체크 중단: Tomcat 미실행 상태"
    exit 2
fi

WAS_HTTP_PORT="${WAS_HTTP_PORT:-28080}"
URL="http://127.0.0.1:${WAS_HTTP_PORT}${CHECK_PATH}"

CURL_CMD=(curl -sS -I --max-time "${TIMEOUT_SEC}" -o /dev/null -w "%{http_code}")

is_success_code() {
    case "$1" in
        200|301|302|303|307|308|401|403) return 0 ;;
        *) return 1 ;;
    esac
}

check_once() {
    if [[ "${DRY_RUN}" == "Y" ]]; then
        log "[DRY-RUN] ${CURL_CMD[*]} \"${URL}\""
        return 0
    fi

    local code
    code="$("${CURL_CMD[@]}" "${URL}" 2>/dev/null || true)"

    if is_success_code "${code}"; then
        log "OK ${code}: ${URL}"
        return 0
    fi

    # 000: 아직 응답 없음 (워밍업 중)
    if [[ "${code}" == "000" ]]; then
        log "WARMING UP (응답 대기 중): ${URL}"
        return 1
    fi

    log "FAIL ${code}: ${URL}"

    if [[ "${VERBOSE}" == "Y" ]]; then
        log "응답 헤더 (상위 20줄):"
        curl -sS -I --max-time "${TIMEOUT_SEC}" "${URL}" 2>/dev/null | head -n 20 || true
    fi

    return 1
}

attempt=1
while (( attempt <= RETRY_N )); do
    log "헬스체크 시도 ${attempt}/${RETRY_N}..."
    if check_once; then
        exit 0
    fi

    (( attempt++ ))
    if (( attempt <= RETRY_N )); then
        sleep "${INTERVAL_SEC}"
    fi
done

log "헬스체크 실패"
exit 1
