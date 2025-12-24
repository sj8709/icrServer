#!/usr/bin/env bash
#
# deploy-war.sh - WAR 배포 스크립트
#
# 실행:
#   ./solution/bin/deploy-war.sh                           # 기본 배포 (재기동 포함)
#   ./solution/bin/deploy-war.sh --no-restart              # 재기동 없이 WAR만 교체
#   ./solution/bin/deploy-war.sh --wait-health             # 배포 후 헬스체크
#   ./solution/bin/deploy-war.sh --war /path/to/app.war    # 특정 WAR 배포
#
# 옵션:
#   --war <path>            배포할 WAR 파일 (기본: packages/${WAR_NAME})
#   --restart               재기동 수행 (기본)
#   --no-restart            재기동 안 함
#   --keep <N>              백업 보관 개수 (기본: 20)
#   --wait-health           배포 후 HTTP 헬스체크 수행
#   --health-path <path>    헬스체크 경로 (기본: /icr/login)
#   --health-retry <N>      재시도 횟수 (기본: 5)
#   --health-interval <sec> 재시도 간격 (기본: 2)
#   --check-https           HTTPS 헬스체크도 추가 수행
#   --dry-run               실제 실행 없이 명령만 출력
#   -h, --help              도움말
#
# 동작:
#   1) 기존 WAR 백업 (INSTALL_BASE/backup/war/)
#   2) 새 WAR 배포
#   3) 오래된 백업 정리
#   4) Tomcat 재기동 (선택)
#   5) 헬스체크 (선택)
#
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"
SOLUTION_HOME="${ROOT_DIR}/solution"
PKG_DIR="${ROOT_DIR}/packages"

# shellcheck disable=SC1090
source "${SOLUTION_HOME}/modules/logging.sh"
source "${SOLUTION_HOME}/modules/service_control.sh"
init_logging "deploy-war"

# ============================================================================
#  옵션 파싱
# ============================================================================

usage() {
    cat <<EOF
사용법:
  deploy-war.sh [옵션]

WAR / 재기동:
  --war <path>            배포할 WAR 파일 (기본: packages/${WAR_NAME})
  --restart               재기동 수행 (기본)
  --no-restart            재기동 안 함
  --keep <N>              백업 보관 개수 (기본: 20)

배포 검증 (선택):
  --wait-health           HTTP 헬스체크 수행
  --health-path <path>    헬스체크 경로 (기본: /icr/login)
  --health-retry <N>      재시도 횟수 (기본: 5)
  --health-interval <sec> 재시도 간격 (기본: 2초)
  --check-https           HTTPS 헬스체크도 추가 수행

기타:
  --dry-run               실제 실행 없이 명령만 출력
  -h, --help              도움말

예시:
  deploy-war.sh                                # 기본 배포
  deploy-war.sh --no-restart                   # WAR만 교체
  deploy-war.sh --wait-health                  # 배포 후 헬스체크
  deploy-war.sh --wait-health --check-https    # HTTP + HTTPS 검증
  deploy-war.sh --war /tmp/new.war --keep 10   # 특정 WAR, 백업 10개 유지
EOF
}

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
        *) die "알 수 없는 옵션: $1 (--help 참조)" ;;
    esac
done

if [[ "${DRY_RUN_LOCAL}" == "Y" ]]; then
    export DRY_RUN="Y"
fi

# ============================================================================
#  설정 로드
# ============================================================================

load_site_conf "${ROOT_DIR}"

if [[ -z "${WAR_SRC}" ]]; then
    WAR_SRC="${PKG_DIR}/${WAR_NAME}"
fi
[[ -f "${WAR_SRC}" ]] || die "WAR 파일 없음: ${WAR_SRC}"

APP_BASE_DIR="${TOMCAT_HOME}/${WAS_APP_BASE}"
WAR_DST="${APP_BASE_DIR}/${WAR_NAME}"

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

[[ -d "${APP_BASE_DIR}" ]] || die "appBase 디렉토리 없음: ${APP_BASE_DIR}"

run "mkdir -p \"${BACKUP_DIR}\""

# ============================================================================
#  1) Stop
# ============================================================================

if [[ "${DO_RESTART}" == "Y" ]]; then
    svc_stop
fi

# ============================================================================
#  2) Backup
# ============================================================================

if [[ -f "${WAR_DST}" ]]; then
    BK="${BACKUP_DIR}/${WAR_NAME}.${TS}"
    log "백업: ${WAR_DST} -> ${BK}"
    run "cp -a \"${WAR_DST}\" \"${BK}\""
else
    log "백업할 기존 WAR 없음"
fi

# ============================================================================
#  3) Deploy
# ============================================================================

log "배포: ${WAR_SRC} -> ${WAR_DST}"
run "cp -a \"${WAR_SRC}\" \"${WAR_DST}\""

# ============================================================================
#  4) Cleanup old backups
# ============================================================================

if [[ "${KEEP_N}" =~ ^[0-9]+$ ]] && (( KEEP_N >= 0 )); then
    log "오래된 백업 정리 (최근 ${KEEP_N}개 유지)"
    if [[ "${DRY_RUN}" == "Y" ]]; then
        log "[DRY-RUN] ls -1t \"${BACKUP_DIR}\"/${WAR_NAME}.* | tail -n +$((KEEP_N+1)) | xargs -r rm -f"
    else
        # shellcheck disable=SC2012
        ls -1t "${BACKUP_DIR}"/${WAR_NAME}.* 2>/dev/null | tail -n +$((KEEP_N+1)) | xargs -r rm -f || true
    fi
fi

# ============================================================================
#  5) Start
# ============================================================================

if [[ "${DO_RESTART}" == "Y" ]]; then
    svc_start
else
    log "재기동 생략 (--no-restart)"
fi

# ============================================================================
#  6) Health check (선택)
# ============================================================================

if [[ "${WAIT_HEALTH}" == "Y" ]]; then
    log "헬스체크 대기 (HTTP)..."

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
        log "헬스체크 (HTTPS)..."

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

log "배포 완료"
