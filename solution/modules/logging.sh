#!/usr/bin/env bash
#
# logging.sh - 스크립트 로깅 모듈
#
# 기능:
#   - 스크립트 실행 로그를 파일과 터미널에 동시 출력
#   - 날짜별 로그 파일 생성 (script-YYYYMMDD.log)
#   - 타임스탬프 포함 로그 출력
#
# 사용법:
#   source "${SOLUTION_HOME}/modules/logging.sh"
#   init_logging "install"
#   log "메시지"
#

# ------------------------------------------------------------------------------
# init_logging - 로그 파일 초기화 및 리다이렉션 설정
#
# 인자:
#   $1 - 스크립트 이름 (예: "install", "start", "deploy-war")
#
# 동작:
#   - solution/logs/ 디렉토리 생성
#   - stdout/stderr를 터미널과 로그 파일에 동시 출력 (tee)
#   - 로그 파일명: {스크립트명}-{YYYYMMDD}.log
#
# 사용 예:
#   init_logging "install"  # -> solution/logs/install-20250115.log
# ------------------------------------------------------------------------------
init_logging() {
    local script_name="$1"
    local date_suffix
    date_suffix="$(date '+%Y%m%d')"

    # SOLUTION_HOME이 없으면 호출한 스크립트 위치 기준으로 계산
    # BASH_SOURCE[1]은 이 함수를 호출한 스크립트의 경로
    local log_dir="${SOLUTION_HOME:-$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)}/logs"
    mkdir -p "${log_dir}"

    local log_file="${log_dir}/${script_name}-${date_suffix}.log"

    # stdout/stderr를 터미널과 파일에 동시 출력
    exec > >(tee -a "${log_file}") 2>&1
}

# ------------------------------------------------------------------------------
# log - 타임스탬프 포함 로그 출력
#
# 인자:
#   $* - 로그 메시지
#
# 출력 형식:
#   [YYYY-MM-DD HH:MM:SS] 메시지
#
# 사용 예:
#   log "서비스 시작"
#   log "포트: ${PORT}"
# ------------------------------------------------------------------------------
log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

# ------------------------------------------------------------------------------
# die - 에러 메시지 출력 후 스크립트 종료
#
# 인자:
#   $* - 에러 메시지
#
# 동작:
#   - stderr로 에러 메시지 출력
#   - exit 1로 스크립트 종료
#
# 사용 예:
#   [[ -f "${FILE}" ]] || die "파일 없음: ${FILE}"
# ------------------------------------------------------------------------------
die() {
    printf '[%s][ERROR] %s\n' "$(date '+%F %T')" "$*" >&2
    exit 1
}
