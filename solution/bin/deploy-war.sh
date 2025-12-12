#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# deploy-war.sh — WAR 전용 재배포 + 선택적 배포 검증
#
# 기본 정책
#  - WAR만 교체
#  - 기존 WAR는 INSTALL_BASE/backup/war 로 백업
#  - 재기동 여부 옵션화
#  - 배포 검증(health)은 옵션으로만 수행
#
# 옵션
#  --war <path>         : 배포할 WAR (기본: packages/icr.war)
#  --no-restart         : WAR 교체 후 재기동 안 함
#  --restart            : (기본) 재기동
#  --keep <N>           : 백업 보관 개수 (기본 20)
#
#  --wait-health        : 재기동 후 health.sh로 서비스 검증
#  --health-path <p>   : health.sh --path (기본: /icr/login)
#  --health-retry <N>  : health 재시도 횟수 (기본 5)
#  --health-interval s : health 재시도 간격(초, 기본 2)
#  --check-https       : health-https.sh 추가 실행
#
#  --dry-run            : 실제 반영 없이 실행 계획만 출력
# -----------------------------------------------------------------------------

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"
PKG_DIR="${ROOT_DIR}/packages"

# 공통 모듈
# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

usage() {
  cat <<'EOF'
Usage:
  deploy-war.sh [options]

WAR / 재기동
  --war <path>         WAR 파일 경로
  --restart            재기동 (기본)
  --no-restart         재기동 안 함
  --keep <N>           백업 보관 개수 (기본 20)

배포 검증(옵션)
  --wait-health        HTTP health 체크 수행
  --health-path <p>   health 경로 (기본: /icr/login)
  --health-retry <N>  재시도 횟수 (기본 5)
  --health-interval s 재시도 간격(초, 기본 2)
  --check-https       HTTPS health도 추가 수행

기타
  --dry-run            DRY RUN
  -h, --help           도움말
EOF
}

# ──────────────────────────────────────────────
# 기본값
# ──────────────────────────────────────────────
WAR_SRC=""
DO_RESTART="Y"
KEEP_N=20

WAIT_HEALTH="N"
HEALTH_PATH="/icr/login"
HEALTH_RETRY=5
HEALTH_INTERVAL=2
CHECK_HTTPS="N"

DRY_RUN_LOCAL="N"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --war) WAR_SRC="${2:-}"; shift 2 ;;
    --restart) DO_RESTART="Y"; shift ;;
    --no-restart) DO_RESTART="N"; shift ;;
    --keep) KEEP_N="${2:-}"; shift 2 ;;

    --wait-health) WAIT_HEALTH="Y"; shift ;;
    --health-path) HEALTH_PATH="${2:-}"; shift 2 ;;
    --health-retry) HEALTH_RETRY="${2:-}"; shift 2 ;;
    --health-interval) HEALTH_INTERVAL="${2:-}"; shift 2 ;;
    --check-https) CHECK_HTTPS="Y"; shift ;;

    --dry-run) DRY_RUN_LOCAL="Y"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

# DRY_RUN 전달
if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
  export DRY_RUN="Y"
fi

# site.conf 로딩
load_site_conf "${ROOT_DIR}"

# 기본 WAR 경로
if [[ -z "${WAR_SRC}" ]]; then
  WAR_SRC="${PKG_DIR}/icr.war"
fi
[[ -f "${WAR_SRC}" ]] || die "WAR not found: ${WAR_SRC}"

APP_BASE_DIR="${TOMCAT_HOME}/${WAS_APP_BASE}"
WAR_DST="${APP_BASE_DIR}/icr.war"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${INSTALL_BASE}/backup/war"

svc_diag
log "WAR_SRC        = ${WAR_SRC}"
log "WAR_DST        = ${WAR_DST}"
log "DO_RESTART     = ${DO_RESTART}"
log "KEEP_N         = ${KEEP_N}"
log "WAIT_HEALTH    = ${WAIT_HEALTH}"
log "HEALTH_PATH    = ${HEALTH_PATH}"
log "CHECK_HTTPS    = ${CHECK_HTTPS}"

[[ -d "${APP_BASE_DIR}" ]] || die "appBase not found: ${APP_BASE_DIR}"

run "mkdir -p \"${BACKUP_DIR}\""

# ──────────────────────────────────────────────
# stop
# ──────────────────────────────────────────────
if [[ "${DO_RESTART}" == "Y" ]]; then
  svc_stop
fi

# ──────────────────────────────────────────────
# backup
# ──────────────────────────────────────────────
if [[ -f "${WAR_DST}" ]]; then
  BK="${BACKUP_DIR}/icr.war.${TS}"
  log "Backup: ${WAR_DST} -> ${BK}"
  run "cp -a \"${WAR_DST}\" \"${BK}\""
else
  log "No existing WAR to backup."
fi

# ──────────────────────────────────────────────
# deploy
# ──────────────────────────────────────────────
log "Deploy: ${WAR_SRC} -> ${WAR_DST}"
run "cp -a \"${WAR_SRC}\" \"${WAR_DST}\""

# ──────────────────────────────────────────────
# backup cleanup
# ──────────────────────────────────────────────
if [[ "${KEEP_N}" =~ ^[0-9]+$ ]] && (( KEEP_N >= 0 )); then
  log "Cleanup backups (keep ${KEEP_N})"
  if [[ "${DRY_RUN}" == "Y" ]]; then
    log "[DRY-RUN] ls -1t \"${BACKUP_DIR}\"/icr.war.* | tail -n +$((KEEP_N+1)) | xargs -r rm -f"
  else
    # shellcheck disable=SC2012
    ls -1t "${BACKUP_DIR}"/icr.war.* 2>/dev/null | tail -n +$((KEEP_N+1)) | xargs -r rm -f || true
  fi
fi

# ──────────────────────────────────────────────
# start
# ──────────────────────────────────────────────
if [[ "${DO_RESTART}" == "Y" ]]; then
  svc_start
else
  log "Restart skipped (--no-restart)."
fi

# ──────────────────────────────────────────────
# health check (선택)
# ──────────────────────────────────────────────
if [[ "${WAIT_HEALTH}" == "Y" ]]; then
  log "Waiting for service health (HTTP)..."

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

  if [[ "${CHECK_HTTPS}" == "Y" ]]; then
    HTTPS_CMD=(
      "${ROOT_DIR}/solution/bin/health-https.sh"
      --path "${HEALTH_PATH}"
    )

    if [[ "${DRY_RUN}" == "Y" ]]; then
      log "[DRY-RUN] ${HTTPS_CMD[*]}"
    else
      "${HTTPS_CMD[@]}"
    fi
  fi

fi

log "Deploy done."

