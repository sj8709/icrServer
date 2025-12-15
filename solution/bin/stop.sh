#!/usr/bin/env bash
#
# stop.sh - Tomcat 중지 스크립트
#
# 실행:
#   ./solution/bin/stop.sh
#
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"
SOLUTION_HOME="${ROOT_DIR}/solution"

# shellcheck disable=SC1090
source "${SOLUTION_HOME}/modules/logging.sh"
source "${SOLUTION_HOME}/modules/service_control.sh"
init_logging "stop"

load_site_conf "${ROOT_DIR}"
svc_diag
svc_stop
