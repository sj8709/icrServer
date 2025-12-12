#!/usr/bin/env bash
#
# service_control.sh - Tomcat 서비스 제어 공통 모듈
#
# 용도:
#   systemd 없이 Tomcat startup/shutdown 스크립트만으로
#   start / stop / restart / status 를 표준화
#
# 사용법:
#   source "${ROOT_DIR}/solution/modules/service_control.sh"
#   load_site_conf "${ROOT_DIR}"
#   svc_start / svc_stop / svc_restart / svc_status
#
# 제공 함수:
#   log()           로그 출력 (타임스탬프 포함)
#   die()           에러 출력 후 종료
#   run()           DRY_RUN 지원 명령 실행
#   load_site_conf()  site.conf 로드 및 필수 변수 검증
#   svc_diag()      진단 정보 출력
#   is_running()    Tomcat 실행 여부 확인
#   svc_status()    상태 출력 (RUNNING/STOPPED)
#   svc_start()     Tomcat 시작
#   svc_stop()      Tomcat 중지 (타임아웃 후 강제종료)
#   svc_restart()   Tomcat 재시작
#   svc_tail()      catalina.out 마지막 N줄 출력
#
# 필수 변수 (site.conf):
#   INSTALL_BASE    설치 기본 경로
#   TOMCAT_HOME     Tomcat 심볼릭 링크 경로
#   WAS_APP_BASE    앱 배포 디렉토리 (상대경로)
#
# 선택 변수 (site.conf):
#   SVC_START_TIMEOUT_SEC       시작 대기 타임아웃 (기본: 30초)
#   SVC_STOP_TIMEOUT_SEC        중지 대기 타임아웃 (기본: 30초)
#   SVC_STOP_FORCEKILL          타임아웃 시 강제종료 (기본: Y)
#   SVC_STOP_FORCEKILL_GRACE_SEC  강제종료 후 대기 (기본: 1초)
#
set -Eeuo pipefail

# ============================================================================
#  로깅 함수
# ============================================================================

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2
  exit 1
}

# ============================================================================
#  실행 헬퍼 (DRY_RUN 지원)
# ============================================================================

: "${DRY_RUN:=N}"

run() {
  log "+ $*"
  if [[ "${DRY_RUN}" == "Y" ]]; then
    return 0
  fi
  eval "$@"
}

# ============================================================================
#  site.conf 로딩
# ============================================================================

load_site_conf() {
  local root_dir="${1:?root_dir required}"
  local conf_file="${root_dir}/solution/config/site.conf"

  [[ -f "${conf_file}" ]] || die "site.conf 없음: ${conf_file}"

  # shellcheck disable=SC1090
  source "${conf_file}"

  # 필수 변수 검증
  : "${INSTALL_BASE:?INSTALL_BASE 미설정}"
  : "${TOMCAT_HOME:?TOMCAT_HOME 미설정}"
  : "${WAS_APP_BASE:?WAS_APP_BASE 미설정}"

  # 서비스 제어 타임아웃 기본값
  : "${SVC_START_TIMEOUT_SEC:=30}"
  : "${SVC_STOP_TIMEOUT_SEC:=30}"
  : "${SVC_STOP_FORCEKILL:=Y}"
  : "${SVC_STOP_FORCEKILL_GRACE_SEC:=1}"

  # 내부 변수 설정
  export __ICR_ROOT_DIR="${root_dir}"
  export __ICR_CONF_FILE="${conf_file}"
}

# ============================================================================
#  진단 출력
# ============================================================================

svc_diag() {
  log "CONF_FILE     = ${__ICR_CONF_FILE:-}"
  log "INSTALL_BASE  = ${INSTALL_BASE:-}"
  log "TOMCAT_HOME   = ${TOMCAT_HOME:-}"
  log "WAS_APP_BASE  = ${WAS_APP_BASE:-}"
  log "MODE          = bin-only (startup/shutdown)"
  log "DRY_RUN       = ${DRY_RUN}"
  log "SVC_START_TIMEOUT_SEC = ${SVC_START_TIMEOUT_SEC}"
  log "SVC_STOP_TIMEOUT_SEC  = ${SVC_STOP_TIMEOUT_SEC}"
  log "SVC_STOP_FORCEKILL    = ${SVC_STOP_FORCEKILL}"
}

# ============================================================================
#  상태 판별
# ============================================================================

is_running() {
  ps -ef | grep -F "${TOMCAT_HOME}" | grep -F "java" | grep -v grep >/dev/null 2>&1
}

svc_status() {
  if is_running; then
    log "Tomcat RUNNING: ${TOMCAT_HOME}"
    return 0
  fi
  log "Tomcat STOPPED: ${TOMCAT_HOME}"
  return 1
}

# ============================================================================
#  시작
# ============================================================================

svc_start() {
  local startup="${TOMCAT_HOME}/bin/startup.sh"
  [[ -x "${startup}" ]] || die "startup.sh 실행 불가: ${startup}"

  if is_running; then
    log "이미 실행 중. 시작 생략."
    return 0
  fi

  log "시작: ${startup}"
  run "\"${startup}\" >/dev/null 2>&1 || true"

  if [[ "${DRY_RUN}" == "Y" ]]; then
    log "[DRY-RUN] 시작 대기 생략"
    return 0
  fi

  local i
  for (( i=1; i<=SVC_START_TIMEOUT_SEC; i++ )); do
    if is_running; then
      log "시작 완료"
      return 0
    fi
    sleep 1
  done

  die "시작 타임아웃 (${SVC_START_TIMEOUT_SEC}초)"
}

# ============================================================================
#  중지
# ============================================================================

svc_stop() {
  local shutdown="${TOMCAT_HOME}/bin/shutdown.sh"
  [[ -x "${shutdown}" ]] || die "shutdown.sh 실행 불가: ${shutdown}"

  if ! is_running; then
    log "이미 중지됨. 중지 생략."
    return 0
  fi

  log "중지: ${shutdown}"
  run "\"${shutdown}\" >/dev/null 2>&1 || true"

  if [[ "${DRY_RUN}" == "Y" ]]; then
    log "[DRY-RUN] 중지 대기/강제종료 생략"
    return 0
  fi

  local i
  for (( i=1; i<=SVC_STOP_TIMEOUT_SEC; i++ )); do
    if ! is_running; then
      log "중지 완료"
      return 0
    fi
    sleep 1
  done

  # 타임아웃 후 강제종료
  if [[ "${SVC_STOP_FORCEKILL}" != "Y" ]]; then
    die "중지 타임아웃 (${SVC_STOP_TIMEOUT_SEC}초). 강제종료 비활성화 상태."
  fi

  log "${SVC_STOP_TIMEOUT_SEC}초 경과. 강제종료 시도..."
  run "pkill -f \"${TOMCAT_HOME}.*java\" || true"
  sleep "${SVC_STOP_FORCEKILL_GRACE_SEC}"

  if ! is_running; then
    log "강제종료 완료"
    return 0
  fi

  die "강제종료 후에도 중지 실패"
}

# ============================================================================
#  재시작
# ============================================================================

svc_restart() {
  svc_stop
  svc_start
}

# ============================================================================
#  로그 tail 헬퍼
# ============================================================================

svc_tail() {
  local n="${1:-200}"
  local f="${TOMCAT_HOME}/logs/catalina.out"

  if [[ -f "${f}" ]]; then
    tail -n "${n}" "${f}"
  else
    log "catalina.out 없음: ${f}"
  fi
}
