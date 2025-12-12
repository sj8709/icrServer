#!/usr/bin/env bash
set -Eeuo pipefail
# -----------------------------------------------------------------------------
# service_control.sh — Tomcat service control (bin-only)
#
# 목적
#  - systemd 없이 Tomcat startup/shutdown 스크립트만으로
#    start / stop / restart / status 를 표준화
#  - stop/start timeout을 site.conf에서 외부화
#
# 의존
#  - solution/config/site.conf
#
# site.conf 관련 변수
#  - INSTALL_BASE
#  - TOMCAT_HOME
#  - WAS_APP_BASE
#
# [Service control tuning]
#  - SVC_START_TIMEOUT_SEC (default: 30)
#  - SVC_STOP_TIMEOUT_SEC  (default: 30)
#  - SVC_STOP_FORCEKILL    (default: Y)
#  - SVC_STOP_FORCEKILL_GRACE_SEC (default: 1)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 로깅 함수
# -----------------------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 실행 헬퍼
# -----------------------------------------------------------------------------
: "${DRY_RUN:=N}"

run() {
  log "+ $*"
  if [[ "${DRY_RUN}" == "Y" ]]; then
    return 0
  fi
  eval "$@"
}

# -----------------------------------------------------------------------------
# site.conf 로딩
# -----------------------------------------------------------------------------
load_site_conf() {
  local root_dir="${1:?root_dir required}"
  local conf_file="${root_dir}/solution/config/site.conf"

  [[ -f "${conf_file}" ]] || die "site.conf not found: ${conf_file}"

  # shellcheck disable=SC1090
  source "${conf_file}"

  : "${INSTALL_BASE:?missing INSTALL_BASE}"
  : "${TOMCAT_HOME:?missing TOMCAT_HOME}"
  : "${WAS_APP_BASE:?missing WAS_APP_BASE}"

  # service control timeout 기본값
  : "${SVC_START_TIMEOUT_SEC:=30}"
  : "${SVC_STOP_TIMEOUT_SEC:=30}"
  : "${SVC_STOP_FORCEKILL:=Y}"
  : "${SVC_STOP_FORCEKILL_GRACE_SEC:=1}"

  export __ICR_ROOT_DIR="${root_dir}"
  export __ICR_CONF_FILE="${conf_file}"
}

# -----------------------------------------------------------------------------
# 진단 출력
# -----------------------------------------------------------------------------
svc_diag() {
  log "CONF_FILE     = ${__ICR_CONF_FILE:-}"
  log "INSTALL_BASE  = ${INSTALL_BASE:-}"
  log "TOMCAT_HOME   = ${TOMCAT_HOME:-}"
  log "WAS_APP_BASE  = ${WAS_APP_BASE:-}"
  log "MODE          = bin-only(startup/shutdown)"
  log "DRY_RUN       = ${DRY_RUN}"
  log "SVC_START_TIMEOUT_SEC = ${SVC_START_TIMEOUT_SEC}"
  log "SVC_STOP_TIMEOUT_SEC  = ${SVC_STOP_TIMEOUT_SEC}"
  log "SVC_STOP_FORCEKILL    = ${SVC_STOP_FORCEKILL}"
}

# -----------------------------------------------------------------------------
# 상태 판별
# -----------------------------------------------------------------------------
is_running() {
  ps -ef | grep -F "${TOMCAT_HOME}" | grep -F "java" | grep -v grep >/dev/null 2>&1
}

svc_status() {
  if is_running; then
    log "Tomcat is RUNNING: ${TOMCAT_HOME}"
    return 0
  fi
  log "Tomcat is STOPPED: ${TOMCAT_HOME}"
  return 1
}

# -----------------------------------------------------------------------------
# start
# -----------------------------------------------------------------------------
svc_start() {
  local startup="${TOMCAT_HOME}/bin/startup.sh"
  [[ -x "${startup}" ]] || die "startup.sh not executable: ${startup}"

  if is_running; then
    log "Already running. Skip start."
    return 0
  fi

  log "Start: ${startup}"
  run "\"${startup}\" >/dev/null 2>&1 || true"

  if [[ "${DRY_RUN}" == "Y" ]]; then
    log "DRY-RUN: skip start wait."
    return 0
  fi

  local i
  for (( i=1; i<=SVC_START_TIMEOUT_SEC; i++ )); do
    if is_running; then
      log "Start OK."
      return 0
    fi
    sleep 1
  done

  die "Start timeout (${SVC_START_TIMEOUT_SEC}s)."
}

# -----------------------------------------------------------------------------
# stop
# -----------------------------------------------------------------------------
svc_stop() {
  local shutdown="${TOMCAT_HOME}/bin/shutdown.sh"
  [[ -x "${shutdown}" ]] || die "shutdown.sh not executable: ${shutdown}"

  if ! is_running; then
    log "Already stopped. Skip stop."
    return 0
  fi

  log "Stop: ${shutdown}"
  run "\"${shutdown}\" >/dev/null 2>&1 || true"

  if [[ "${DRY_RUN}" == "Y" ]]; then
    log "DRY-RUN: skip stop wait/force-kill."
    return 0
  fi

  local i
  for (( i=1; i<=SVC_STOP_TIMEOUT_SEC; i++ )); do
    if ! is_running; then
      log "Stop OK."
      return 0
    fi
    sleep 1
  done

  if [[ "${SVC_STOP_FORCEKILL}" != "Y" ]]; then
    die "Stop timeout (${SVC_STOP_TIMEOUT_SEC}s). Force kill disabled."
  fi

  log "Still running after ${SVC_STOP_TIMEOUT_SEC}s. Force kill..."
  run "pkill -f \"${TOMCAT_HOME}.*java\" || true"
  sleep "${SVC_STOP_FORCEKILL_GRACE_SEC}"

  if ! is_running; then
    log "Force kill OK."
    return 0
  fi

  die "Stop timeout (even after force kill)."
}

# -----------------------------------------------------------------------------
# restart
# -----------------------------------------------------------------------------
svc_restart() {
  svc_stop
  svc_start
}

# -----------------------------------------------------------------------------
# log tail helper
# -----------------------------------------------------------------------------
svc_tail() {
  local n="${1:-200}"
  local f="${TOMCAT_HOME}/logs/catalina.out"

  if [[ -f "${f}" ]]; then
    tail -n "${n}" "${f}"
  else
    log "No catalina.out: ${f}"
  fi
}

