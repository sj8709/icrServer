#!/usr/bin/env bash
#
# ICR 솔루션 - Tomcat 설치/연동 코어 스크립트
# (solution/bin/install-core.sh)
#
# 기능 요약
# - site.conf 를 읽어서 사이트별 설정 로드
# - packages/ 내 Tomcat tgz 설치 및 TOMCAT_HOME 심볼릭 링크 구성
# - templates/tomcat/*.tpl → INSTALL_BASE/config/tomcat/*.xml, setenv.sh 생성
#   - 기본(KEEP): 파일이 이미 존재하면 유지
#   - 강제(FORCE): ICR_FORCE_REGEN=Y 이면 기존 파일을 .bak.YYYYMMDD_HHMMSS 로 백업 후 재생성
# - server.xml 은 포트 / appBase / HTTPS 플래그에 따라 템플릿 치환
# - web.xml, context.xml, setenv.sh 는 템플릿에서 복사 (필요 토큰만 치환)
# - 외부 datasource yml(icr-datasource.yml) 생성/import는 사용하지 않음
# - packages/icr.war → TOMCAT_HOME/appBase(icr-webapps)/icr.war 배포
#   - 기본(KEEP): 이미 존재하면 유지
#   - 강제(FORCE): ICR_FORCE_REGEN=Y 이면 기존 WAR 백업 후 교체
#
# 실행 예
#   기본(유지):               ./install.sh
#   강제 갱신(백업+재생성):    ICR_FORCE_REGEN=Y ./install.sh
#
set -euo pipefail

# 강제 갱신 옵션 (Y면 템플릿 산출물/war 강제 교체)
: "${ICR_FORCE_REGEN:=N}"

# ──────────────────────────────────────────────
# 공통 유틸
# ──────────────────────────────────────────────
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

    # KEEP 모드: 이미 있으면 유지
    if [[ -f "${target}" && "${ICR_FORCE_REGEN}" != "Y" ]]; then
        log "${label} 이미 존재 → 유지: ${target}"
        return 0
    fi

    # FORCE 모드: 이미 있으면 백업 후 재생성
    if [[ -f "${target}" && "${ICR_FORCE_REGEN}" == "Y" ]]; then
        log "${label} 강제 갱신 (ICR_FORCE_REGEN=Y)"
        backup_if_exists "${target}"
    else
        log "${label} 생성"
    fi

    "${render_fn}" "${target}"
}

# ──────────────────────────────────────────────
# 경로 설정
# ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SOLUTION_HOME="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_DIR="$(cd "${SOLUTION_HOME}/.." && pwd)"

SITE_CONF="${SOLUTION_HOME}/config/site.conf"
TEMPLATE_TOMCAT_DIR="${SOLUTION_HOME}/templates/tomcat"
PACKAGES_DIR="${BASE_DIR}/packages"

# ──────────────────────────────────────────────
# 1. site.conf 로드
# ──────────────────────────────────────────────
load_site_conf() {
    log "site.conf 로드: ${SITE_CONF}"

    if [[ ! -f "${SITE_CONF}" ]]; then
        die "site.conf 파일을 찾을 수 없습니다: ${SITE_CONF}"
    fi

    # shellcheck source=/dev/null
    . "${SITE_CONF}"

    # 기본값 처리 (site.conf 에 없을 경우)
    : "${TOMCAT_DIST_NAME:=apache-tomcat-10.1.50}"
    : "${TOMCAT_HOME:=/opt/tomcat}"
    : "${INSTALL_BASE:=/opt/icr-solution}"
    : "${WAS_ENABLE_HTTPS:=N}"

    # JVM 기본값 (site.conf 에 없을 때)
    : "${JVM_XMS:=512m}"
    : "${JVM_XMX:=1024m}"
    : "${JVM_TIMEZONE:=Asia/Seoul}"
    : "${JVM_ENCODING:=UTF-8}"

    # External config 기본값 (site.conf 에 없으면 INSTALL_BASE/config)
    : "${ICR_CONFIG_DIR:=${INSTALL_BASE}/config}"

    # 필수값 검증
    if [[ -z "${SITE:-}" ]]; then
        die "SITE 값이 site.conf 에 설정되어 있지 않습니다."
    fi
    if [[ -z "${ENV:-}" ]]; then
        die "ENV 값이 site.conf 에 설정되어 있지 않습니다."
    fi
    if [[ -z "${WAS_HTTP_PORT:-}" ]]; then
        die "WAS_HTTP_PORT 값이 site.conf 에 설정되어 있지 않습니다."
    fi
    if [[ -z "${WAS_APP_BASE:-}" ]]; then
        die "WAS_APP_BASE 값이 site.conf 에 설정되어 있지 않습니다."
    fi
    if [[ -z "${JASYPT_ENCRYPTOR_PASSWORD:-}" ]]; then
        die "JASYPT_ENCRYPTOR_PASSWORD 값이 site.conf 에 설정되어 있지 않습니다."
    fi

    TOMCAT_TGZ_NAME="${TOMCAT_DIST_NAME}.tar.gz"

    log "SITE=${SITE}, ENV=${ENV}"
    log "INSTALL_BASE=${INSTALL_BASE}"
    log "TOMCAT_HOME=${TOMCAT_HOME}"
    log "TOMCAT_DIST_NAME=${TOMCAT_DIST_NAME}"
    log "WAS_HTTP_PORT=${WAS_HTTP_PORT}, WAS_HTTPS_PORT=${WAS_HTTPS_PORT:-'(미사용)'}"
    log "WAS_ENABLE_HTTPS=${WAS_ENABLE_HTTPS}"
    log "WAS_APP_BASE=${WAS_APP_BASE}"
    log "JVM_XMS=${JVM_XMS}, JVM_XMX=${JVM_XMX}"
    log "JVM_TIMEZONE=${JVM_TIMEZONE}, JVM_ENCODING=${JVM_ENCODING}"
    log "ICR_CONFIG_DIR=${ICR_CONFIG_DIR}"
}

# ──────────────────────────────────────────────
# 2. INSTALL_BASE 및 Tomcat config 디렉토리 준비
# ──────────────────────────────────────────────
prepare_install_base() {
    log "INSTALL_BASE 디렉토리 준비: ${INSTALL_BASE}"

    mkdir -p "${INSTALL_BASE}"
    mkdir -p "${INSTALL_BASE}/config/tomcat"
    mkdir -p "${INSTALL_BASE}/logs"
    mkdir -p "${INSTALL_BASE}/data"

    SITE_TOMCAT_CONFIG_DIR="${INSTALL_BASE}/config/tomcat"
    log "Tomcat 설정 디렉토리: ${SITE_TOMCAT_CONFIG_DIR}"
}

# ──────────────────────────────────────────────
# 3. Tomcat 설치 또는 버전 스위칭
# ──────────────────────────────────────────────
install_or_switch_tomcat() {
    local tgz="${PACKAGES_DIR}/${TOMCAT_TGZ_NAME}"

    log "Tomcat 패키지 확인: ${tgz}"
    if [[ ! -f "${tgz}" ]]; then
        die "Tomcat 패키지 파일이 없습니다: ${tgz}"
    fi

    # TOMCAT_HOME 의 부모 디렉토리 기준으로 설치
    local tomcat_parent
    tomcat_parent="$(dirname "${TOMCAT_HOME}")"
    local tomcat_target="${tomcat_parent}/${TOMCAT_DIST_NAME}"

    log "Tomcat 설치 대상 디렉토리: ${tomcat_target}"

    if [[ ! -d "${tomcat_target}" ]]; then
        log "Tomcat 디렉토리가 없어 새로 압축 해제합니다."
        mkdir -p "${tomcat_parent}"
        tar xzf "${tgz}" -C "${tomcat_parent}"
    else
        log "Tomcat 디렉토리가 이미 존재합니다. (재사용)"
    fi

    # TOMCAT_HOME 심볼릭 링크 교체
    log "TOMCAT_HOME 심볼릭 링크 설정: ${TOMCAT_HOME} -> ${tomcat_target}"
    if [[ -L "${TOMCAT_HOME}" || -e "${TOMCAT_HOME}" ]]; then
        rm -rf "${TOMCAT_HOME}"
    fi
    ln -s "${tomcat_target}" "${TOMCAT_HOME}"

    # 기본 webapps 정리 + appBase 디렉토리 준비
    local webapps_dir="${tomcat_target}/webapps"
    local app_base_dir="${tomcat_target}/${WAS_APP_BASE}"

    if [[ -d "${webapps_dir}" ]]; then
        log "기본 webapps 정리 (ROOT, docs, examples 등 삭제)"
        rm -rf "${webapps_dir:?}/"*
    fi

    mkdir -p "${app_base_dir}"
    log "appBase 디렉토리 보장: ${app_base_dir}"

    # Tomcat 주요 디렉토리 확인
    if [[ ! -d "${TOMCAT_HOME}/conf" ]]; then
        die "Tomcat conf 디렉토리가 존재하지 않습니다: ${TOMCAT_HOME}/conf"
    fi
    if [[ ! -d "${TOMCAT_HOME}/bin" ]]; then
        die "Tomcat bin 디렉토리가 존재하지 않습니다: ${TOMCAT_HOME}/bin"
    fi
}

# ──────────────────────────────────────────────
# 4. server.xml 템플릿 렌더링 (포트/HTTPS/appBase 치환)
# ──────────────────────────────────────────────
render_server_xml() {
    local dst="$1"
    local tmp="${dst}.tmp"

    log "server.xml 템플릿 렌더링 → ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/server.xml.tpl" ]]; then
        die "server.xml.tpl 템플릿을 찾을 수 없습니다: ${TEMPLATE_TOMCAT_DIR}/server.xml.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/server.xml.tpl" "${tmp}"

    # 기본 토큰 치환 (포트 / appBase)
    sed -i \
        -e "s|@WAS_HTTP_PORT@|${WAS_HTTP_PORT}|g" \
        -e "s|@WAS_HTTPS_PORT@|${WAS_HTTPS_PORT:-8443}|g" \
        -e "s|@WAS_APP_BASE@|${WAS_APP_BASE}|g" \
        "${tmp}"

    # HTTPS 플래그 처리
    if [[ "${WAS_ENABLE_HTTPS}" == "Y" ]]; then
        log "HTTPS 활성화: HTTPS Connector 블럭 그대로 유지"
        # 단순히 마커만 제거
        sed -i \
            -e "s|@HTTPS_CONNECTOR_BEGIN@||g" \
            -e "s|@HTTPS_CONNECTOR_END@||g" \
            "${tmp}"
    else
        log "HTTPS 비활성화: HTTPS Connector 블럭 주석 처리"

        # 마커 포함 블럭 전체를 XML 주석으로 감싸기
        local tmp2="${tmp}.2"
        awk '
            /@HTTPS_CONNECTOR_BEGIN@/ {
                if (!in_https) {
                    print "<!-- HTTPS connector block disabled by install-core";
                    in_https = 1;
                }
                print $0;
                next;
            }
            /@HTTPS_CONNECTOR_END@/ {
                print $0;
                if (in_https) {
                    print "HTTPS connector block end -->";
                    in_https = 0;
                }
                next;
            }
            { print $0; }
        ' "${tmp}" > "${tmp2}"
        mv "${tmp2}" "${tmp}"
    fi

    mv "${tmp}" "${dst}"
}

# ──────────────────────────────────────────────
# 5. web.xml 템플릿 복사
# ──────────────────────────────────────────────
render_web_xml() {
    local dst="$1"
    log "web.xml 템플릿 복사 → ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/web.xml.tpl" ]]; then
        die "web.xml.tpl 템플릿을 찾을 수 없습니다: ${TEMPLATE_TOMCAT_DIR}/web.xml.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/web.xml.tpl" "${dst}"
}

# ──────────────────────────────────────────────
# 6. context.xml 템플릿 복사
# ──────────────────────────────────────────────
render_context_xml() {
    local dst="$1"
    log "context.xml 템플릿 복사 → ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/context.xml.tpl" ]]; then
        die "context.xml.tpl 템플릿을 찾을 수 없습니다: ${TEMPLATE_TOMCAT_DIR}/context.xml.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/context.xml.tpl" "${dst}"
}

# ──────────────────────────────────────────────
# 7. setenv.sh 템플릿 렌더링 (+ ENV/SITE/JVM/CONFIG/Jasypt 치환)
# ──────────────────────────────────────────────
render_setenv_sh() {
    local dst="$1"
    local tmp="${dst}.tmp"

    log "setenv.sh 템플릿 렌더링 → ${dst}"

    if [[ ! -f "${TEMPLATE_TOMCAT_DIR}/setenv.sh.tpl" ]]; then
        die "setenv.sh.tpl 템플릿을 찾을 수 없습니다: ${TEMPLATE_TOMCAT_DIR}/setenv.sh.tpl"
    fi

    cp "${TEMPLATE_TOMCAT_DIR}/setenv.sh.tpl" "${tmp}"

    # 토큰 치환 (슬래시 포함 값 안전하게 | 사용)
    sed -i \
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

# ──────────────────────────────────────────────
# 8. Tomcat 설정 파일 생성/갱신 (템플릿 기준 4종)
# ──────────────────────────────────────────────
ensure_site_config() {
    if [[ "${ICR_FORCE_REGEN}" == "Y" ]]; then
        log "Tomcat 설정 파일 강제 갱신 모드 (ICR_FORCE_REGEN=Y)"
    else
        log "Tomcat 설정 파일 생성 (없을 때만)"
    fi

    local server_xml="${SITE_TOMCAT_CONFIG_DIR}/server.xml"
    local context_xml="${SITE_TOMCAT_CONFIG_DIR}/context.xml"
    local web_xml="${SITE_TOMCAT_CONFIG_DIR}/web.xml"
    local setenv_sh="${SITE_TOMCAT_CONFIG_DIR}/setenv.sh"

    ensure_generated_file "${server_xml}"  render_server_xml   "server.xml"
    ensure_generated_file "${context_xml}" render_context_xml  "context.xml"
    ensure_generated_file "${web_xml}"     render_web_xml      "web.xml"
    ensure_generated_file "${setenv_sh}"   render_setenv_sh    "setenv.sh"
}

# ──────────────────────────────────────────────
# 9. Tomcat 실제 conf/bin 에 심볼릭 링크 연결
# ──────────────────────────────────────────────
link_tomcat_with_site_config() {
    log "Tomcat conf/bin 을 config/tomcat 와 링크"

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
    log "  ${server_xml_link}  -> ${SITE_TOMCAT_CONFIG_DIR}/server.xml"
    log "  ${context_xml_link} -> ${SITE_TOMCAT_CONFIG_DIR}/context.xml"
    log "  ${web_xml_link}     -> ${SITE_TOMCAT_CONFIG_DIR}/web.xml"
    log "  ${setenv_sh_link}   -> ${SITE_TOMCAT_CONFIG_DIR}/setenv.sh"
}

# ──────────────────────────────────────────────
# 10. WAR 배포 (packages/icr.war → TOMCAT_HOME/appBase/icr.war)
# ──────────────────────────────────────────────
deploy_war() {
    local src_war="${PACKAGES_DIR}/icr.war"
    local dst_dir="${TOMCAT_HOME}/${WAS_APP_BASE}"
    local dst_war="${dst_dir}/icr.war"

    log "WAR 배포: ${src_war} -> ${dst_war}"

    if [[ ! -f "${src_war}" ]]; then
        die "WAR 파일이 없습니다: ${src_war}"
    fi

    mkdir -p "${dst_dir}"

    if [[ -f "${dst_war}" && "${ICR_FORCE_REGEN}" != "Y" ]]; then
        log "icr.war 이미 존재 → 유지: ${dst_war}"
        return 0
    fi

    if [[ -f "${dst_war}" && "${ICR_FORCE_REGEN}" == "Y" ]]; then
        log "icr.war 강제 교체 (ICR_FORCE_REGEN=Y)"
        backup_if_exists "${dst_war}"
    else
        log "icr.war 신규 배포"
    fi

    cp -f "${src_war}" "${dst_war}"
    log "WAR 배포 완료: ${dst_war}"
}

# ──────────────────────────────────────────────
# 11. 스크립트 실행 권한 설정
# ──────────────────────────────────────────────
ensure_script_permissions() {
    log "스크립트 실행 권한 설정"

    # solution/bin/*.sh
    chmod +x "${SOLUTION_HOME}/bin/"*.sh 2>/dev/null || true

    # solution/modules/*.sh
    chmod +x "${SOLUTION_HOME}/modules/"*.sh 2>/dev/null || true

    # 루트 스크립트 (install.sh, uninstall.sh)
    chmod +x "${BASE_DIR}/"*.sh 2>/dev/null || true

    # Tomcat bin 스크립트
    if [[ -d "${TOMCAT_HOME}/bin" ]]; then
        chmod +x "${TOMCAT_HOME}/bin/"*.sh 2>/dev/null || true
    fi

    log "실행 권한 설정 완료"
}

# ──────────────────────────────────────────────
# 메인 실행 흐름
# ──────────────────────────────────────────────
main() {
    log "ICR 솔루션 Tomcat 설치/연동 시작"

    load_site_conf
    prepare_install_base
    install_or_switch_tomcat
    ensure_site_config
    link_tomcat_with_site_config
    deploy_war
    ensure_script_permissions

    log "ICR 솔루션 Tomcat 설치/연동 완료"
}

main "$@"

