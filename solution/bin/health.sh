#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# health.sh — ICR 서비스 헬스체크 (HTTP 전용, WARMING UP 표시)
#
# 정책
#  - 실제 서비스 URL만 체크 (기본: /icr/login)
#  - HTTP만 사용
#
# 성공 판정 코드
#  - 200 / 30x / 401 / 403
#
# WARMING UP
#  - curl이 HTTP 코드를 못 받으면(000) 아직 포트/앱이 뜨는 중일 수 있음
#  - 이 경우 FAIL 대신 WARMING UP으로 출력 (재시도 계속)
#
# 옵션
#  --path <path>       : 체크 경로 변경 (기본: /icr/login)
#  --timeout <sec>     : curl timeout (기본 5초)
#  --retry <N>         : 재시도 횟수 (기본 3)
#  --interval <sec>    : 재시도 간격 (기본 1초)
#  --verbose           : 실패 시 응답 헤더 출력(000 제외)
#  --dry-run           : curl 명령만 출력
# -----------------------------------------------------------------------------

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"

# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

usage() {
  cat <<'EOF'
Usage:
  health.sh [options]

Options:
  --path <path>       check path (default: /icr/login)
  --timeout <sec>     curl timeout (default: 5)
  --retry <N>         retry count (default: 3)
  --interval <sec>    retry interval seconds (default: 1)
  --verbose           print response headers on failure (except 000)
  --dry-run           dry run
  -h, --help          help
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
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
  export DRY_RUN="Y"
fi

load_site_conf "${ROOT_DIR}"
svc_diag

if ! is_running; then
  log "Health check abort: Tomcat is not running."
  exit 2
fi

WAS_HTTP_PORT="${WAS_HTTP_PORT:-28080}"
URL="http://127.0.0.1:${WAS_HTTP_PORT}${CHECK_PATH}"

# HEAD 요청으로 코드만 확인
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

  # 000: 아직 리슨/응답 전(워밍업), 또는 네트워크/포트 문제
  # 배포 직후에는 워밍업이 흔하므로 FAIL 대신 WARMING UP으로 출력
  if [[ "${code}" == "000" ]]; then
    log "WARMING UP (no response yet): ${URL}"
    return 1
  fi

  log "FAIL ${code}: ${URL}"

  if [[ "${VERBOSE}" == "Y" ]]; then
    log "Headers(head 20):"
    curl -sS -I --max-time "${TIMEOUT_SEC}" "${URL}" 2>/dev/null | head -n 20 || true
  fi

  return 1
}

attempt=1
while (( attempt <= RETRY_N )); do
  log "Health attempt ${attempt}/${RETRY_N}..."
  if check_once; then
    exit 0
  fi

  (( attempt++ ))
  if (( attempt <= RETRY_N )); then
    sleep "${INTERVAL_SEC}"
  fi
done

log "Health check FAILED."
exit 1

