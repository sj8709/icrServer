#!/usr/bin/env bash
#
# install-core.sh - ICR 솔루션 Tomcat 설치 코어 스크립트
#
# 실행:
#   ./install.sh                       # 기본 설치 (래퍼 경유)
#   ./solution/bin/install-core.sh     # 직접 실행
#
# 환경변수:
#   ICR_FORCE_REGEN=Y ./install.sh     # 설정 파일 강제 재생성 (기존 백업 후 덮어쓰기)
#
set -euo pipefail

: "${ICR_FORCE_REGEN:=N}"

# ============================================================================
#  [1] 공통 유틸리티
# ============================================================================

# ------------------------------------------------------------------------------
# log - 표준 로그 메시지 출력
#
# Arguments:
#   $* - 출력할 메시지
# ------------------------------------------------------------------------------
log() {
    echo "[install-core] $*"
}

# ------------------------------------------------------------------------------
# die - 에러 메시지 출력 후 스크립트 종료
#
# Arguments:
#   $* - 에러 메시지
# Exit:
#   1 - 항상 에러 코드 1로 종료
# ------------------------------------------------------------------------------
die() {
    echo "[install-core][ERROR] $*" >&2
    exit 1
}

# ------------------------------------------------------------------------------
# backup_if_exists - 파일이 존재하면 타임스탬프 기반 백업 생성
#
# Arguments:
#   $1 - 백업할 파일 경로
# Output:
#   파일명.bak.YYYYMMDD_HHMMSS 형태로 백업 생성
# ------------------------------------------------------------------------------
backup_if_exists() {
    local f="$1"
    if [[ -f "${f}" ]]; then
        local bak="${f}.bak.$(date +%Y%m%d_%H%M%S)"
        cp -f "${f}" "${bak}"
        log "백업 생성: ${bak}"
    fi
}

# ------------------------------------------------------------------------------
# detect_arch - 시스템 CPU 아키텍처 감지
#
# Returns:
#   stdout - "x64" (Intel/AMD) 또는 "arm" (ARM64)
# Exit:
#   1 - 지원하지 않는 아키텍처일 경우
# ------------------------------------------------------------------------------
detect_arch() {
    local arch
    arch="$(uname -m)"

    case "${arch}" in
        x86_64|amd64)
            echo "x64"
            ;;
        aarch64|arm64)
            echo "arm"
            ;;
        *)
            die "지원하지 않는 아키텍처: ${arch}
    -> 지원 아키텍처: x86_64(x64), aarch64(arm64)"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# ensure_generated_file - 설정 파일 생성/갱신 관리
#
# ICR_FORCE_REGEN 환경변수에 따라 파일 생성 여부 결정:
#   - 파일 없음: 새로 생성
#   - 파일 있음 + ICR_FORCE_REGEN=N: 기존 유지
#   - 파일 있음 + ICR_FORCE_REGEN=Y: 백업 후 재생성
#
# Arguments:
#   $1 - 대상 파일 경로
#   $2 - 렌더링 함수명 (render_server_xml 등)
#   $3 - 로그용 라벨 (server.xml 등)
# ------------------------------------------------------------------------------
ensure_generated_file() {
    local target="$1"
    local render_fn="$2"
    local label="$3"

    if [[ -f "${target}" && "${ICR_FORCE_REGEN}" != "Y" ]]; then
        log "${label} 이미 존재 -> 유지: ${target}"
        return 0
    fi

    if [[ -f "${target}" && "${ICR_FORCE_REGEN}" == "Y" ]]; then
        log "${label} 강제 갱신 (ICR_FORCE_REGEN=Y)"
        backup_if_exists "${target}"
    else
        log "${label} 생성"
    fi

    "${render_fn}" "${target}"
}

# ============================================================================
#  [2] 경로 설정
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SOLUTION_HOME="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_DIR="$(cd "${SOLUTION_HOME}/.." && pwd)"

SITE_CONF="${SOLUTION_HOME}/config/site.conf"
TEMPLATE_TOMCAT_DIR="${SOLUTION_HOME}/templates/tomcat"
PACKAGES_DIR="${BASE_DIR}/packages"

# ============================================================================
#  [3] 설정 로드 및 검증
# ============================================================================

# ------------------------------------------------------------------------------
# load_site_conf - site.conf 설정 파일 로드 및 기본값 설정
#
# 수행 작업:
#   1. site.conf 파일 존재 확인 및 source
#   2. 미설정 변수에 기본값 할당
#   3. validate_required_vars() 호출하여 필수값 검증
#   4. 로드된 설정값 로그 출력
#
# Globals (설정됨):
#   JAVA_SOURCE, TOMCAT_DIST_NAME, TOMCAT_HOME, INSTALL_BASE,
#   WAS_ENABLE_HTTPS, WAS_SHUTDOWN_PORT, JVM_XMS, JVM_XMX 등
# ------------------------------------------------------------------------------
load_site_conf() {
    log "site.conf 로드: ${SITE_CONF}"

    if [[ ! -f "${SITE_CONF}" ]]; then
        die "site.conf 파일 없음: ${SITE_CONF}"
    fi

    # shellcheck source=/dev/null
    . "${SITE_CONF}"

    # --- 기본값 설정 ---
    : "${JAVA_SOURCE:=system}"
    : "${TOMCAT_DIST_NAME:=apache-tomcat-10.1.50}"
    : "${TOMCAT_HOME:=/opt/tomcat}"
    : "${INSTALL_BASE:=/opt/icr-solution}"
    : "${WAS_ENABLE_HTTPS:=N}"
    : "${WAS_SHUTDOWN_PORT:=8005}"
    : "${WAS_SSL_KEYSTORE_FILE:=localhost-rsa.jks}"
    : "${WAS_SSL_KEYSTORE_PASSWORD:=changeit}"
    : "${JVM_XMS:=512m}"
    : "${JVM_XMX:=1024m}"
    : "${JVM_TIMEZONE:=Asia/Seoul}"
    : "${JVM_ENCODING:=UTF-8}"
    : "${ICR_CONFIG_DIR:=${INSTALL_BASE}/config}"

    # --- 필수값 검증 ---
    validate_required_vars

    TOMCAT_TGZ_NAME="${TOMCAT_DIST_NAME}.tar.gz"

    # --- 설정 출력 ---
    log "SITE=${SITE}, ENV=${ENV}"
    log "JAVA_SOURCE=${JAVA_SOURCE}"
    log "JAVA_HOME=${JAVA_HOME:-'(bundled 모드: 자동 설정)'}"
    log "INSTALL_BASE=${INSTALL_BASE}"
    log "TOMCAT_HOME=${TOMCAT_HOME}"
    log "TOMCAT_DIST_NAME=${TOMCAT_DIST_NAME}"
    log "WAS_HTTP_PORT=${WAS_HTTP_PORT}, WAS_HTTPS_PORT=${WAS_HTTPS_PORT:-'(미사용)'}"
    log "WAS_ENABLE_HTTPS=${WAS_ENABLE_HTTPS}"
    log "WAS_APP_BASE=${WAS_APP_BASE}"
    log "JVM_XMS=${JVM_XMS}, JVM_XMX=${JVM_XMX}"
}

# ------------------------------------------------------------------------------
# validate_required_vars - 필수 설정 변수 검증
#
# 검증 항목:
#   - SITE: 사이트 식별자
#   - ENV: Spring 프로파일
#   - JAVA_SOURCE: system|bundled 값 검증
#   - JAVA_HOME: system 모드일 때 경로 및 실행파일 검증
#   - WAS_HTTP_PORT, WAS_APP_BASE, JASYPT_ENCRYPTOR_PASSWORD
#
# Exit:
#   1 - 검증 실패 시
# ------------------------------------------------------------------------------
validate_required_vars() {
    # SITE
    if [[ -z "${SITE:-}" ]]; then
        die "SITE 미설정. site.conf에 SITE=xxx 추가 필요"
    fi

    # ENV
    if [[ -z "${ENV:-}" ]]; then
        die "ENV 미설정. site.conf에 ENV=dev|prod 추가 필요"
    fi

    # JAVA_SOURCE 검증
    if [[ "${JAVA_SOURCE}" != "system" && "${JAVA_SOURCE}" != "bundled" ]]; then
        die "JAVA_SOURCE 값 오류: ${JAVA_SOURCE}
    -> 허용값: system, bundled"
    fi

    # JAVA_HOME 검증 (system 모드일 때만)
    if [[ "${JAVA_SOURCE}" == "system" ]]; then
        if [[ -z "${JAVA_HOME:-}" ]]; then
            die "JAVA_HOME 미설정. JAVA_SOURCE=system 일 때 JAVA_HOME 필수
    -> site.conf에 JAVA_HOME=/path/to/jdk 추가 필요
    -> 또는 JAVA_SOURCE=bundled 로 변경하여 번들 Java 사용"
        fi
        if [[ ! -d "${JAVA_HOME}" ]]; then
            die "JAVA_HOME 경로 없음: ${JAVA_HOME}
    -> 서버에 JDK 설치 여부 확인: ls -d /usr/lib/jvm/*
    -> site.conf의 JAVA_HOME 경로 수정
    -> 또는 JAVA_SOURCE=bundled 로 변경하여 번들 Java 사용"
        fi
        if [[ ! -x "${JAVA_HOME}/bin/java" ]]; then
            die "java 실행파일 없음: ${JAVA_HOME}/bin/java
    -> JDK 설치 상태 확인 필요"
        fi
    fi
    # bundled 모드일 때 JAVA_HOME은 install_bundled_java()에서 자동 설정됨

    # WAS_HTTP_PORT
    if [[ -z "${WAS_HTTP_PORT:-}" ]]; then
        die "WAS_HTTP_PORT 미설정. site.conf에 WAS_HTTP_PORT=8080 추가 필요"
    fi

    # WAS_APP_BASE
    if [[ -z "${WAS_APP_BASE:-}" ]]; then
        die "WAS_APP_BASE 미설정. site.conf에 WAS_APP_BASE=icr-webapps 추가 필요"
    fi

    # JASYPT_ENCRYPTOR_PASSWORD
    if [[ -z "${JASYPT_ENCRYPTOR_PASSWORD:-}" ]]; then
        die "JASYPT_ENCRYPTOR_PASSWORD 미설정. site.conf에 추가 필요"
    fi
}

# ============================================================================
#  [4] 디렉토리 준비
# ============================================================================

# ------------------------------------------------------------------------------
# prepare_install_base - 설치 기본 디렉토리 구조 생성
#
# 생성되는 디렉토리:
#   - $INSTALL_BASE/
#   - $INSTALL_BASE/config/tomcat/  (Tomcat 설정 파일용)
#   - $INSTALL_BASE/logs/           (로그 디렉토리)
#   - $INSTALL_BASE/data/           (데이터 디렉토리)
#
# Globals (설정됨):
#   SITE_TOMCAT_CONFIG_DIR - Tomcat 설정 파일 경로
# ------------------------------------------------------------------------------
prepare_install_base() {
    log "INSTALL_BASE 디렉토리 준비: ${INSTALL_BASE}"

    mkdir -p "${INSTALL_BASE}"
    mkdir -p "${INSTALL_BASE}/config/tomcat"
    mkdir -p "${INSTALL_BASE}/logs"
    mkdir -p "${INSTALL_BASE}/data"

    SITE_TOMCAT_CONFIG_DIR="${INSTALL_BASE}/config/tomcat"
    log "Tomcat 설정 디렉토리: ${SITE_TOMCAT_CONFIG_DIR}"
}

# ------------------------------------------------------------------------------
# install_or_switch_tomcat - Tomcat 설치 또는 버전 전환
#
# 수행 작업:
#   1. packages/에서 Tomcat tgz 파일 확인
#   2. INSTALL_BASE에 압축 해제 (이미 있으면 재사용)
#   3. TOMCAT_HOME 심볼릭 링크 생성/갱신
#   4. 기본 webapps 디렉토리 정리
#   5. WAS_APP_BASE 디렉토리 생성
#
# Prerequisites:
#   - packages/${TOMCAT_DIST_NAME}.tar.gz 파일 필요
# ------------------------------------------------------------------------------
install_or_switch_tomcat() {
    local tgz="${PACKAGES_DIR}/${TOMCAT_TGZ_NAME}"

    log "Tomcat 패키지 확인: ${tgz}"
    if [[ ! -f "${tgz}" ]]; then
        die "Tomcat 패키지 없음: ${tgz}
    -> packages/ 디렉토리에 ${TOMCAT_TGZ_NAME} 파일 필요"
    fi

    local tomcat_parent
    tomcat_parent="$(dirname "${TOMCAT_HOME}")"
    local tomcat_target="${tomcat_parent}/${TOMCAT_DIST_NAME}"

    log "Tomcat 설치 대상: ${tomcat_target}"

    if [[ ! -d "${tomcat_target}" ]]; then
        log "Tomcat 압축 해제"
        mkdir -p "${tomcat_parent}"
        tar xzf "${tgz}" -C "${tomcat_parent}"
    else
        log "Tomcat 디렉토리 존재 (재사용)"
    fi

    # 심볼릭 링크 설정
    log "TOMCAT_HOME 심볼릭 링크: ${TOMCAT_HOME} -> ${tomcat_target}"
    if [[ -L "${TOMCAT_HOME}" || -e "${TOMCAT_HOME}" ]]; then
        rm -rf "${TOMCAT_HOME}"
    fi
    ln -s "${tomcat_target}" "${TOMCAT_HOME}"

    # 기본 webapps 정리 + appBase 준비
    local webapps_dir="${tomcat_target}/webapps"
    local app_base_dir="${tomcat_target}/${WAS_APP_BASE}"

    if [[ -d "${webapps_dir}" ]]; then
        log "기본 webapps 정리"
        rm -rf "${webapps_dir:?}/"*
    fi

    mkdir -p "${app_base_dir}"
    log "appBase 디렉토리: ${app_base_dir}"

    # 필수 디렉토리 확인
    if [[ ! -d "${TOMCAT_HOME}/conf" ]]; then
        die "Tomcat conf 디렉토리 없음: ${TOMCAT_HOME}/conf"
    fi
    if [[ ! -d "${TOMCAT_HOME}/bin" ]]; then
        die "Tomcat bin 디렉토리 없음: ${TOMCAT_HOME}/bin"
    fi
}

# ------------------------------------------------------------------------------
# install_bundled_java - 번들 JDK 설치 (JAVA_SOURCE=bundled 모드)
#
# 수행 작업:
#   1. detect_arch()로 시스템 아키텍처 감지 (x64/arm)
#   2. 아키텍처에 맞는 JDK 번들 파일 선택
#   3. INSTALL_BASE에 압축 해제 (이미 있으면 재사용)
#   4. $INSTALL_BASE/java 심볼릭 링크 생성
#   5. JAVA_HOME 전역 변수 자동 설정
#   6. java 실행파일 검증 및 버전 출력
#
# Prerequisites:
#   - packages/JDK21_x64.tar.gz (Intel/AMD) 또는
#   - packages/JDK21_arm.tar.gz (ARM64)
#
# Globals (설정됨):
#   JAVA_HOME - 설치된 Java 경로 ($INSTALL_BASE/java)
# ------------------------------------------------------------------------------
install_bundled_java() {
    log "번들 Java 설치 시작"

    # 아키텍처 감지
    local arch
    arch="$(detect_arch)"
    log "감지된 아키텍처: ${arch}"

    # 아키텍처별 번들 파일 매핑
    local java_tgz
    case "${arch}" in
        x64)
            java_tgz="${PACKAGES_DIR}/JDK21_x64.tar.gz"
            ;;
        arm)
            java_tgz="${PACKAGES_DIR}/JDK21_arm.tar.gz"
            ;;
    esac

    log "Java 번들 파일: ${java_tgz}"

    if [[ ! -f "${java_tgz}" ]]; then
        die "Java 번들 파일 없음: ${java_tgz}
    -> packages/ 디렉토리에 JDK21_x64.tar.gz 또는 JDK21_arm.tar.gz 파일 필요
    -> 또는 JAVA_SOURCE=system 으로 변경하여 시스템 Java 사용"
    fi

    # 번들에서 디렉토리명 추출 (첫 번째 경로 컴포넌트)
    # NOTE: pipefail 환경에서 head가 파이프를 닫으면 tar가 SIGPIPE를 받아 종료됨
    #       || true로 파이프라인 실패를 무시 (결과는 정상 캡처됨)
    local java_dir_name
    java_dir_name="$(tar -tzf "${java_tgz}" 2>/dev/null | head -1 | cut -d'/' -f1)" || true

    if [[ -z "${java_dir_name}" ]]; then
        die "Java 번들 구조 파싱 실패: ${java_tgz}"
    fi

    log "Java 디렉토리명: ${java_dir_name}"

    local java_target="${INSTALL_BASE}/${java_dir_name}"
    local java_link="${INSTALL_BASE}/java"

    # Java 압축 해제
    if [[ ! -d "${java_target}" ]]; then
        log "Java 압축 해제: ${java_tgz} -> ${INSTALL_BASE}/"
        tar xzf "${java_tgz}" -C "${INSTALL_BASE}"
    else
        log "Java 디렉토리 존재 (재사용): ${java_target}"
    fi

    # 심볼릭 링크 설정
    log "Java 심볼릭 링크: ${java_link} -> ${java_target}"
    if [[ -L "${java_link}" || -e "${java_link}" ]]; then
        rm -rf "${java_link}"
    fi
    ln -s "${java_target}" "${java_link}"

    # JAVA_HOME 자동 설정 (전역 변수 업데이트)
    JAVA_HOME="${java_link}"
    log "JAVA_HOME 자동 설정: ${JAVA_HOME}"

    # Java 실행파일 검증
    if [[ ! -x "${JAVA_HOME}/bin/java" ]]; then
        die "번들 Java 설치 후 java 실행파일 없음: ${JAVA_HOME}/bin/java
    -> 번들 파일 손상 가능성. 다시 다운로드 필요"
    fi

    # 버전 확인 로그
    local java_version
    java_version="$("${JAVA_HOME}/bin/java" -version 2>&1 | head -1)"
    log "Java 버전: ${java_version}"

    log "번들 Java 설치 완료"
}

# ============================================================================
#  [5] 템플릿 렌더링
# ============================================================================

# ------------------------------------------------------------------------------
# render_server_xml - server.xml 템플릿 렌더링
#
# 수행 작업:
#   1. server.xml.tpl 템플릿에서 주석(#) 제거
#   2. @TOKEN@ 플레이스홀더를 실제 값으로 치환
#   3. WAS_ENABLE_HTTPS에 따라 HTTPS Connector 블럭 처리
#
# Arguments:
#   $1 - 출력 파일 경로
#
# 치환 토큰:
#   @WAS_SHUTDOWN_PORT@, @WAS_HTTP_PORT@, @WAS_HTTPS_PORT@,
#   @WAS_APP_BASE@, @WAS_SSL_KEYSTORE_FILE@, @WAS_SSL_KEYSTORE_PASSWORD@
# ------------------------------------------------------------------------------
render_server_xml() {
    local dst="$1"
    local tmp="${dst}.tmp"

    log "server.xml 렌더링 -> ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/server.xml.tpl" ]]; then
        die "템플릿 없음: ${TEMPLATE_TOMCAT_DIR}/server.xml.tpl"
    fi

    # 템플릿 주석(#) 제거 후 복사
    grep -v '^#' "${TEMPLATE_TOMCAT_DIR}/server.xml.tpl" > "${tmp}"

    # 토큰 치환
    sed -i \
        -e "s|@WAS_SHUTDOWN_PORT@|${WAS_SHUTDOWN_PORT}|g" \
        -e "s|@WAS_HTTP_PORT@|${WAS_HTTP_PORT}|g" \
        -e "s|@WAS_HTTPS_PORT@|${WAS_HTTPS_PORT:-8443}|g" \
        -e "s|@WAS_APP_BASE@|${WAS_APP_BASE}|g" \
        -e "s|@WAS_SSL_KEYSTORE_FILE@|${WAS_SSL_KEYSTORE_FILE}|g" \
        -e "s|@WAS_SSL_KEYSTORE_PASSWORD@|${WAS_SSL_KEYSTORE_PASSWORD}|g" \
        "${tmp}"

    # HTTPS 플래그 처리
    if [[ "${WAS_ENABLE_HTTPS}" == "Y" ]]; then
        log "HTTPS 활성화: Connector 블럭 유지"
        sed -i \
            -e "s|.*@HTTPS_CONNECTOR_BEGIN@.*||g" \
            -e "s|.*@HTTPS_CONNECTOR_END@.*||g" \
            "${tmp}"
    else
        log "HTTPS 비활성화: Connector 블럭 삭제"
        local tmp2="${tmp}.2"
        awk '
            /@HTTPS_CONNECTOR_BEGIN@/ { in_https = 1; next; }
            /@HTTPS_CONNECTOR_END@/   { in_https = 0; next; }
            !in_https { print $0; }
        ' "${tmp}" > "${tmp2}"
        mv "${tmp2}" "${tmp}"
    fi

    mv "${tmp}" "${dst}"
}

# ------------------------------------------------------------------------------
# render_web_xml - web.xml 템플릿 복사
#
# Arguments:
#   $1 - 출력 파일 경로
# ------------------------------------------------------------------------------
render_web_xml() {
    local dst="$1"
    log "web.xml 복사 -> ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/web.xml.tpl" ]]; then
        die "템플릿 없음: ${TEMPLATE_TOMCAT_DIR}/web.xml.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/web.xml.tpl" "${dst}"
}

# ------------------------------------------------------------------------------
# render_context_xml - context.xml 템플릿 복사
#
# Arguments:
#   $1 - 출력 파일 경로
# ------------------------------------------------------------------------------
render_context_xml() {
    local dst="$1"
    log "context.xml 복사 -> ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/context.xml.tpl" ]]; then
        die "템플릿 없음: ${TEMPLATE_TOMCAT_DIR}/context.xml.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/context.xml.tpl" "${dst}"
}

# ------------------------------------------------------------------------------
# render_setenv_sh - setenv.sh 템플릿 렌더링
#
# Tomcat 시작 시 자동 로드되는 JVM 환경 설정 파일 생성.
#
# Arguments:
#   $1 - 출력 파일 경로
#
# 치환 토큰:
#   @JAVA_HOME@, @ENV@, @SITE@, @JVM_XMS@, @JVM_XMX@,
#   @JVM_ENCODING@, @JVM_TIMEZONE@, @ICR_CONFIG_DIR@,
#   @JASYPT_ENCRYPTOR_PASSWORD@
# ------------------------------------------------------------------------------
render_setenv_sh() {
    local dst="$1"
    local tmp="${dst}.tmp"

    log "setenv.sh 렌더링 -> ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/setenv.sh.tpl" ]]; then
        die "템플릿 없음: ${TEMPLATE_TOMCAT_DIR}/setenv.sh.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/setenv.sh.tpl" "${tmp}"

    # 토큰 치환
    sed -i \
        -e "s|@JAVA_HOME@|${JAVA_HOME}|g" \
        -e "s|@ENV@|${ENV}|g" \
        -e "s|@SITE@|${SITE}|g" \
        -e "s|@JVM_XMS@|${JVM_XMS}|g" \
        -e "s|@JVM_XMX@|${JVM_XMX}|g" \
        -e "s|@JVM_ENCODING@|${JVM_ENCODING}|g" \
        -e "s|@JVM_TIMEZONE@|${JVM_TIMEZONE}|g" \
        -e "s|@ICR_CONFIG_DIR@|${ICR_CONFIG_DIR}|g" \
        -e "s|@JASYPT_ENCRYPTOR_PASSWORD@|${JASYPT_ENCRYPTOR_PASSWORD}|g" \
        -e "s|@INSTALL_BASE@|${INSTALL_BASE}|g" \
        "${tmp}"

    mv "${tmp}" "${dst}"
    chmod +x "${dst}"
}

# ============================================================================
#  [6] 설정 파일 생성 및 링크
# ============================================================================

# ------------------------------------------------------------------------------
# ensure_site_config - 사이트별 Tomcat 설정 파일 생성
#
# SITE_TOMCAT_CONFIG_DIR에 다음 파일들을 생성:
#   - server.xml   (Tomcat 서버 설정)
#   - context.xml  (컨텍스트 설정)
#   - web.xml      (웹 애플리케이션 설정)
#   - setenv.sh    (JVM 환경 설정)
#
# ICR_FORCE_REGEN=Y 시 기존 파일 백업 후 재생성
# ------------------------------------------------------------------------------
ensure_site_config() {
    if [[ "${ICR_FORCE_REGEN}" == "Y" ]]; then
        log "설정 파일 강제 갱신 모드"
    else
        log "설정 파일 생성 (없을 때만)"
    fi

    local server_xml="${SITE_TOMCAT_CONFIG_DIR}/server.xml"
    local context_xml="${SITE_TOMCAT_CONFIG_DIR}/context.xml"
    local web_xml="${SITE_TOMCAT_CONFIG_DIR}/web.xml"
    local setenv_sh="${SITE_TOMCAT_CONFIG_DIR}/setenv.sh"

    ensure_generated_file "${server_xml}"  render_server_xml  "server.xml"
    ensure_generated_file "${context_xml}" render_context_xml "context.xml"
    ensure_generated_file "${web_xml}"     render_web_xml     "web.xml"
    ensure_generated_file "${setenv_sh}"   render_setenv_sh   "setenv.sh"
}

# ------------------------------------------------------------------------------
# link_tomcat_with_site_config - Tomcat 설정 파일 심볼릭 링크 연결
#
# SITE_TOMCAT_CONFIG_DIR의 설정 파일들을 Tomcat conf/bin에 심볼릭 링크로 연결.
# 이를 통해 설정 파일을 INSTALL_BASE/config/tomcat/에서 중앙 관리.
#
# 생성되는 링크:
#   $TOMCAT_HOME/conf/server.xml  -> $SITE_TOMCAT_CONFIG_DIR/server.xml
#   $TOMCAT_HOME/conf/context.xml -> $SITE_TOMCAT_CONFIG_DIR/context.xml
#   $TOMCAT_HOME/conf/web.xml     -> $SITE_TOMCAT_CONFIG_DIR/web.xml
#   $TOMCAT_HOME/bin/setenv.sh    -> $SITE_TOMCAT_CONFIG_DIR/setenv.sh
# ------------------------------------------------------------------------------
link_tomcat_with_site_config() {
    log "Tomcat conf/bin 심볼릭 링크 설정"

    local server_xml_link="${TOMCAT_HOME}/conf/server.xml"
    local context_xml_link="${TOMCAT_HOME}/conf/context.xml"
    local web_xml_link="${TOMCAT_HOME}/conf/web.xml"
    local setenv_sh_link="${TOMCAT_HOME}/bin/setenv.sh"

    mkdir -p "${TOMCAT_HOME}/conf"
    mkdir -p "${TOMCAT_HOME}/bin"

    ln -sf "${SITE_TOMCAT_CONFIG_DIR}/server.xml"  "${server_xml_link}"
    ln -sf "${SITE_TOMCAT_CONFIG_DIR}/context.xml" "${context_xml_link}"
    ln -sf "${SITE_TOMCAT_CONFIG_DIR}/web.xml"     "${web_xml_link}"
    ln -sf "${SITE_TOMCAT_CONFIG_DIR}/setenv.sh"   "${setenv_sh_link}"

    log "링크 완료:"
    log "  ${server_xml_link} -> server.xml"
    log "  ${context_xml_link} -> context.xml"
    log "  ${web_xml_link} -> web.xml"
    log "  ${setenv_sh_link} -> setenv.sh"
}

# ============================================================================
#  [7] 검증
# ============================================================================

# ------------------------------------------------------------------------------
# validate_ssl_config - SSL/HTTPS 설정 검증
#
# WAS_ENABLE_HTTPS=Y 일 때만 실행.
#
# 검증 항목:
#   - SSL 인증서 파일(keystore) 존재 여부
#   - 기본 샘플 인증서 사용 시 경고 출력
#
# Exit:
#   1 - 인증서 파일이 없는 경우
# ------------------------------------------------------------------------------
validate_ssl_config() {
    if [[ "${WAS_ENABLE_HTTPS}" != "Y" ]]; then
        return 0
    fi

    log "SSL 인증서 검증..."

    local keystore_path="${TOMCAT_HOME}/conf/${WAS_SSL_KEYSTORE_FILE}"

    if [[ ! -f "${keystore_path}" ]]; then
        die "HTTPS 활성화됨, 인증서 파일 없음: ${keystore_path}
    -> ${TOMCAT_HOME}/conf/ 에 인증서 파일 배치 필요
    -> 또는 site.conf에서 WAS_ENABLE_HTTPS=N 으로 변경"
    fi

    if [[ "${WAS_SSL_KEYSTORE_FILE}" == "localhost-rsa.jks" ]] && \
       [[ "${WAS_SSL_KEYSTORE_PASSWORD}" == "changeit" ]]; then
        log "========================================="
        log "[경고] 기본 샘플 인증서 사용 중"
        log "       운영환경에서는 실제 인증서로 교체 필요"
        log "========================================="
    fi

    log "SSL 인증서 검증 완료: ${keystore_path}"
}

# ============================================================================
#  [8] WAR 배포
# ============================================================================

# ------------------------------------------------------------------------------
# deploy_war - WAR 파일 배포
#
# packages/icr.war 파일을 Tomcat appBase 디렉토리에 복사.
#
# 동작:
#   - 이미 존재하고 ICR_FORCE_REGEN=N: 기존 유지
#   - 이미 존재하고 ICR_FORCE_REGEN=Y: 백업 후 교체
#   - 존재하지 않음: 신규 배포
#
# Prerequisites:
#   - packages/icr.war 파일 필요
# ------------------------------------------------------------------------------
deploy_war() {
    local src_war="${PACKAGES_DIR}/icr.war"
    local dst_dir="${TOMCAT_HOME}/${WAS_APP_BASE}"
    local dst_war="${dst_dir}/icr.war"

    log "WAR 배포: ${src_war} -> ${dst_war}"

    if [[ ! -f "${src_war}" ]]; then
        die "WAR 파일 없음: ${src_war}
    -> packages/ 디렉토리에 icr.war 파일 필요"
    fi

    mkdir -p "${dst_dir}"

    if [[ -f "${dst_war}" && "${ICR_FORCE_REGEN}" != "Y" ]]; then
        log "icr.war 이미 존재 -> 유지"
        return 0
    fi

    if [[ -f "${dst_war}" && "${ICR_FORCE_REGEN}" == "Y" ]]; then
        log "icr.war 강제 교체"
        backup_if_exists "${dst_war}"
    else
        log "icr.war 신규 배포"
    fi

    cp -f "${src_war}" "${dst_war}"
    log "WAR 배포 완료"
}

# ============================================================================
#  [9] 실행 권한 설정
# ============================================================================

# ------------------------------------------------------------------------------
# ensure_script_permissions - 스크립트 실행 권한 설정
#
# 다음 디렉토리의 .sh 파일들에 실행 권한(+x) 부여:
#   - $SOLUTION_HOME/bin/*.sh
#   - $SOLUTION_HOME/modules/*.sh
#   - $BASE_DIR/*.sh
#   - $TOMCAT_HOME/bin/*.sh
#
# Windows에서 Git으로 체크아웃 시 권한 손실 복구용
# ------------------------------------------------------------------------------
ensure_script_permissions() {
    log "스크립트 실행 권한 설정"

    chmod +x "${SOLUTION_HOME}/bin/"*.sh 2>/dev/null || true
    chmod +x "${SOLUTION_HOME}/modules/"*.sh 2>/dev/null || true
    chmod +x "${BASE_DIR}/"*.sh 2>/dev/null || true

    if [[ -d "${TOMCAT_HOME}/bin" ]]; then
        chmod +x "${TOMCAT_HOME}/bin/"*.sh 2>/dev/null || true
    fi

    log "실행 권한 설정 완료"
}

# ============================================================================
#  메인 실행
# ============================================================================

# ------------------------------------------------------------------------------
# main - 설치 메인 함수
#
# 실행 순서:
#   1. load_site_conf()           - 설정 로드
#   2. prepare_install_base()     - 디렉토리 구조 생성
#   3. install_bundled_java()     - 번들 Java 설치 (옵션)
#   4. install_or_switch_tomcat() - Tomcat 설치
#   5. validate_ssl_config()      - SSL 검증
#   6. ensure_site_config()       - 설정 파일 생성
#   7. link_tomcat_with_site_config() - 심볼릭 링크
#   8. deploy_war()               - WAR 배포
#   9. ensure_script_permissions() - 권한 설정
# ------------------------------------------------------------------------------
main() {
    log "========================================="
    log "ICR 솔루션 Tomcat 설치 시작"
    log "========================================="

    load_site_conf
    prepare_install_base

    # 번들 Java 설치 (JAVA_SOURCE=bundled 일 때)
    if [[ "${JAVA_SOURCE}" == "bundled" ]]; then
        install_bundled_java
    fi

    install_or_switch_tomcat
    validate_ssl_config
    ensure_site_config
    link_tomcat_with_site_config
    deploy_war
    ensure_script_permissions

    log "========================================="
    log "ICR 솔루션 Tomcat 설치 완료"
    log "========================================="
}

main "$@"
