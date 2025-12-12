#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# health-https.sh — ICR HTTPS 헬스체크(분리본)
#
# 목적
#  - HTTPS 커넥터/인증서/포트 리슨 여부를 별도로 점검
#  - 평소에는 안 쓰고(노이즈 방지), HTTPS 이슈 트러블슈팅 시에만 사용
#
# 기본
#  - 체크 경로: /icr/login
#  - HTTPS 포트: site.conf의 WAS_HTTPS_PORT (없으면 28443)
#
# 성공 판정 코드
#  - 200 / 30x / 401 / 403
#
# 옵션
#  --path <path>       : 체크 경로 변경 (기본: /icr/login)
#  --timeout <sec>     : curl timeout (기본 5초)
#  --retry <N>         : 재시도 횟수 (기본 3)
#  --interval <sec>    : 재시도 간격 (기본 1초)
#  --verify            : 인증서 검증 ON (기본은 -k로 검증 OFF)
#  --verbose           : 실패 시 헤더 출력
#  --dry-run           : curl 명령만 출력
# -----------------------------------------------------------------------------

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"

# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

usage() {
  cat <<'EOF'
Usage:
  health-https.sh [options]

Options:
  --path <path>       check path (default: /icr/login)
  --timeout <sec>     curl timeout (default: 5)
  --retry <N>         retry count (default: 3)
  --interval <sec>    retry interval seconds (default: 1)
  --verify            enable TLS cert verification (default: insecure -k)
  --verbose           print response headers on failure
  --dry-run           dry run
  -h, --help          help
EOF
}

CHECK_PATH="/icr/login"
TIMEOUT_SEC=5
RETRY_N=3
INTERVAL_SEC=1
VERIFY_TLS="N"   # 기본은 -k(검증 OFF)
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
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
  export DRY_RUN="Y"
fi

load_site_conf "${ROOT_DIR}"
svc_diag

if ! is_running; then
  log "HTTPS health abort: Tomcat is not running."
  exit 2
fi

WAS_HTTPS_PORT="${WAS_HTTPS_PORT:-28443}"
URL="https://127.0.0.1:${WAS_HTTPS_PORT}${CHECK_PATH}"

# HEAD 요청으로 코드만 확인
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

  # 000이면 TLS/연결 자체 실패 가능성이 큼
  if [[ "${code}" == "000" ]]; then
    log "FAIL 000 (connect/tls): ${URL}"
  else
    log "FAIL ${code}: ${URL}"
  fi

  if [[ "${VERBOSE}" == "Y" ]]; then
    log "Headers(head 20):"
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
  log "HTTPS health attempt ${attempt}/${RETRY_N}..."

  if check_once; then
    exit 0
  fi

  (( attempt++ ))
  if (( attempt <= RETRY_N )); then
    sleep "${INTERVAL_SEC}"
  fi
done

log "HTTPS health FAILED."
exit 1

