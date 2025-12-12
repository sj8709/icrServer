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

log() {
    echo "[install-core] $*"
}

die() {
    echo "[install-core][ERROR] $*" >&2
    exit 1
}

backup_if_exists() {
    local f="$1"
    if [[ -f "${f}" ]]; then
        local bak="${f}.bak.$(date +%Y%m%d_%H%M%S)"
        cp -f "${f}" "${bak}"
        log "백업 생성: ${bak}"
    fi
}

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

load_site_conf() {
    log "site.conf 로드: ${SITE_CONF}"

    if [[ ! -f "${SITE_CONF}" ]]; then
        die "site.conf 파일 없음: ${SITE_CONF}"
    fi

    # shellcheck source=/dev/null
    . "${SITE_CONF}"

    # --- 기본값 설정 ---
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
    log "JAVA_HOME=${JAVA_HOME}"
    log "INSTALL_BASE=${INSTALL_BASE}"
    log "TOMCAT_HOME=${TOMCAT_HOME}"
    log "TOMCAT_DIST_NAME=${TOMCAT_DIST_NAME}"
    log "WAS_HTTP_PORT=${WAS_HTTP_PORT}, WAS_HTTPS_PORT=${WAS_HTTPS_PORT:-'(미사용)'}"
    log "WAS_ENABLE_HTTPS=${WAS_ENABLE_HTTPS}"
    log "WAS_APP_BASE=${WAS_APP_BASE}"
    log "JVM_XMS=${JVM_XMS}, JVM_XMX=${JVM_XMX}"
}

validate_required_vars() {
    # SITE
    if [[ -z "${SITE:-}" ]]; then
        die "SITE 미설정. site.conf에 SITE=xxx 추가 필요"
    fi

    # ENV
    if [[ -z "${ENV:-}" ]]; then
        die "ENV 미설정. site.conf에 ENV=dev|prod 추가 필요"
    fi

    # JAVA_HOME (경로 + 실행파일 검증)
    if [[ -z "${JAVA_HOME:-}" ]]; then
        die "JAVA_HOME 미설정. site.conf에 JAVA_HOME=/path/to/jdk 추가 필요"
    fi
    if [[ ! -d "${JAVA_HOME}" ]]; then
        die "JAVA_HOME 경로 없음: ${JAVA_HOME}
    -> 서버에 JDK 설치 여부 확인: ls -d /usr/lib/jvm/*
    -> site.conf의 JAVA_HOME 경로 수정"
    fi
    if [[ ! -x "${JAVA_HOME}/bin/java" ]]; then
        die "java 실행파일 없음: ${JAVA_HOME}/bin/java
    -> JDK 설치 상태 확인 필요"
    fi

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

prepare_install_base() {
    log "INSTALL_BASE 디렉토리 준비: ${INSTALL_BASE}"

    mkdir -p "${INSTALL_BASE}"
    mkdir -p "${INSTALL_BASE}/config/tomcat"
    mkdir -p "${INSTALL_BASE}/logs"
    mkdir -p "${INSTALL_BASE}/data"

    SITE_TOMCAT_CONFIG_DIR="${INSTALL_BASE}/config/tomcat"
    log "Tomcat 설정 디렉토리: ${SITE_TOMCAT_CONFIG_DIR}"
}

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

# ============================================================================
#  [5] 템플릿 렌더링
# ============================================================================

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

render_web_xml() {
    local dst="$1"
    log "web.xml 복사 -> ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/web.xml.tpl" ]]; then
        die "템플릿 없음: ${TEMPLATE_TOMCAT_DIR}/web.xml.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/web.xml.tpl" "${dst}"
}

render_context_xml() {
    local dst="$1"
    log "context.xml 복사 -> ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/context.xml.tpl" ]]; then
        die "템플릿 없음: ${TEMPLATE_TOMCAT_DIR}/context.xml.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/context.xml.tpl" "${dst}"
}

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
        "${tmp}"

    mv "${tmp}" "${dst}"
    chmod +x "${dst}"
}

# ============================================================================
#  [6] 설정 파일 생성 및 링크
# ============================================================================

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

main() {
    log "========================================="
    log "ICR 솔루션 Tomcat 설치 시작"
    log "========================================="

    load_site_conf
    prepare_install_base
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
