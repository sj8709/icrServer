#!/usr/bin/env bash
#
# health-https.sh - HTTPS 헬스체크 스크립트
#
# 실행:
#   ./solution/bin/health-https.sh                    # 기본 체크
#   ./solution/bin/health-https.sh --path /api/ping   # 경로 지정
#   ./solution/bin/health-https.sh --verify           # 인증서 검증 ON
#   ./solution/bin/health-https.sh --verbose          # 실패 시 상세 출력
#
# 옵션:
#   --path <path>       체크 경로 (기본: /icr/login)
#   --timeout <sec>     curl 타임아웃 (기본: 5초)
#   --retry <N>         재시도 횟수 (기본: 3)
#   --interval <sec>    재시도 간격 (기본: 1초)
#   --verify            TLS 인증서 검증 ON (기본: OFF)
#   --verbose           실패 시 응답 헤더 출력
#   --dry-run           실제 실행 없이 명령만 출력
#   -h, --help          도움말
#
# 용도:
#   - HTTPS 커넥터/인증서/포트 점검
#   - 평소에는 사용 안 함 (노이즈 방지)
#   - HTTPS 이슈 트러블슈팅 시에만 사용
#
# 성공 판정:
#   HTTP 200, 30x, 401, 403
#
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"
SOLUTION_HOME="${ROOT_DIR}/solution"

# shellcheck disable=SC1090
source "${SOLUTION_HOME}/modules/logging.sh"
source "${SOLUTION_HOME}/modules/service_control.sh"
init_logging "health-https"

# ============================================================================
#  옵션 파싱
# ============================================================================

usage() {
    cat <<EOF
사용법:
  health-https.sh [옵션]

옵션:
  --path <path>       체크 경로 (기본: /icr/login)
  --timeout <sec>     curl 타임아웃 (기본: 5초)
  --retry <N>         재시도 횟수 (기본: 3)
  --interval <sec>    재시도 간격 (기본: 1초)
  --verify            TLS 인증서 검증 ON (기본: OFF, -k 사용)
  --verbose           실패 시 응답 헤더 출력
  --dry-run           실제 실행 없이 명령만 출력
  -h, --help          도움말

예시:
  health-https.sh                      # 기본 체크
  health-https.sh --path /api/health   # 경로 지정
  health-https.sh --verify             # 인증서 검증
  health-https.sh --retry 5 --verbose  # 5회 재시도 + 상세 출력
EOF
}

CHECK_PATH="/icr/login"
TIMEOUT_SEC=5
RETRY_N=3
INTERVAL_SEC=1
VERIFY_TLS="N"
VERBOSE="N"
DRY_RUN_LOCAL="N"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) CHECK_PATH="${2:-}"; shift 2 ;;
        --timeout) TIMEOUT_SEC="${2:-}"; shift 2 ;;
        --retry) RETRY_N="${2:-}"; shift 2 ;;
        --interval) INTERVAL_SEC="${2:-}"; shift 2 ;;
        --verify) VERIFY_TLS="Y"; shift ;;
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
    log "HTTPS 헬스체크 중단: Tomcat 미실행 상태"
    exit 2
fi

WAS_HTTPS_PORT="${WAS_HTTPS_PORT:-28443}"
URL="https://127.0.0.1:${WAS_HTTPS_PORT}${CHECK_PATH}"

CURL_CMD=(curl -sS -I --max-time "${TIMEOUT_SEC}" -o /dev/null -w "%{http_code}")
if [[ "${VERIFY_TLS}" != "Y" ]]; then
    CURL_CMD+=( -k )
fi

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

    if [[ "${code}" == "000" ]]; then
        log "FAIL 000 (연결/TLS 오류): ${URL}"
    else
        log "FAIL ${code}: ${URL}"
    fi

    if [[ "${VERBOSE}" == "Y" ]]; then
        log "응답 헤더 (상위 20줄):"
        if [[ "${VERIFY_TLS}" == "Y" ]]; then
            curl -sS -I --max-time "${TIMEOUT_SEC}" "${URL}" 2>/dev/null | head -n 20 || true
        else
            curl -sS -I --max-time "${TIMEOUT_SEC}" -k "${URL}" 2>/dev/null | head -n 20 || true
        fi
    fi

    return 1
}

attempt=1
while (( attempt <= RETRY_N )); do
    log "HTTPS 헬스체크 시도 ${attempt}/${RETRY_N}..."

    if check_once; then
        exit 0
    fi

    (( attempt++ ))
    if (( attempt <= RETRY_N )); then
        sleep "${INTERVAL_SEC}"
    fi
done

log "HTTPS 헬스체크 실패"
exit 1
