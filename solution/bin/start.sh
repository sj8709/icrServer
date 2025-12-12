#!/usr/bin/env bash
#
# start.sh - Tomcat 시작 스크립트
#
# 실행:
#   ./solution/bin/start.sh
#
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SELF_DIR}/../.." && pwd)"

# shellcheck disable=SC1090
source "${ROOT_DIR}/solution/modules/service_control.sh"

load_site_conf "${ROOT_DIR}"
svc_diag
svc_start
