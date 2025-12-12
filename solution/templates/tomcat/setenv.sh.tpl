#!/usr/bin/env bash
#
# setenv.sh - Tomcat JVM 환경 설정
#
# 생성: install-core.sh에 의해 템플릿에서 자동 생성
# 위치: $INSTALL_BASE/config/tomcat/setenv.sh -> $TOMCAT_HOME/bin/setenv.sh (심볼릭 링크)
#
# 이 파일은 Tomcat 시작 시 자동으로 로드되어 JAVA_OPTS, CATALINA_OPTS 등을 설정합니다.
# 직접 수정하지 마세요. 변경이 필요하면 site.conf 수정 후 재설치하세요.
#

# ============================================================================
#  1. Java 환경
# ============================================================================

export JAVA_HOME="@JAVA_HOME@"
export PATH="$JAVA_HOME/bin:$PATH"

# ============================================================================
#  2. Catalina 출력 설정
# ============================================================================

# catalina.out 비활성화 (로그는 Log4j2/Logback으로 관리)
export CATALINA_OUT=/dev/null

# ============================================================================
#  3. JVM 메모리 설정
# ============================================================================

# 힙 메모리: 초기(-Xms) / 최대(-Xmx)
export JAVA_OPTS="$JAVA_OPTS -Xms@JVM_XMS@ -Xmx@JVM_XMX@"

# ============================================================================
#  4. JVM 시스템 프로퍼티
# ============================================================================

# 파일 인코딩
export JAVA_OPTS="$JAVA_OPTS -Dfile.encoding=@JVM_ENCODING@"

# 타임존
export JAVA_OPTS="$JAVA_OPTS -Duser.timezone=@JVM_TIMEZONE@"

# ============================================================================
#  5. Spring Boot 설정
# ============================================================================

# 활성 프로파일
export JAVA_OPTS="$JAVA_OPTS -Dspring.profiles.active=@ENV@"

# 사이트 식별자
export JAVA_OPTS="$JAVA_OPTS -Dicr.site=@SITE@"

# 외부 설정 디렉토리
export ICR_CONFIG_DIR="@ICR_CONFIG_DIR@"
export JAVA_OPTS="$JAVA_OPTS -Dicr.config.dir=${ICR_CONFIG_DIR}"

# ============================================================================
#  6. 보안 설정
# ============================================================================

# Jasypt 암호화 키 (application.yml 암호화된 값 복호화용)
export JAVA_OPTS="$JAVA_OPTS -Djasypt.encryptor.password=@JASYPT_ENCRYPTOR_PASSWORD@"

# ============================================================================
#  7. 추가 JVM 옵션 (필요시 주석 해제)
# ============================================================================

# GC 설정 (Java 17+에서는 G1GC가 기본)
# export JAVA_OPTS="$JAVA_OPTS -XX:+UseG1GC"
# export JAVA_OPTS="$JAVA_OPTS -XX:MaxGCPauseMillis=200"

# GC 로그 (Java 17+ 형식)
# export JAVA_OPTS="$JAVA_OPTS -Xlog:gc*:file=${CATALINA_HOME}/logs/gc.log:time,uptime:filecount=5,filesize=10M"

# 힙 덤프 (OOM 발생 시 자동 생성)
# export JAVA_OPTS="$JAVA_OPTS -XX:+HeapDumpOnOutOfMemoryError"
# export JAVA_OPTS="$JAVA_OPTS -XX:HeapDumpPath=${CATALINA_HOME}/logs/"

# JMX 원격 모니터링 (보안상 운영환경 비권장)
# export JAVA_OPTS="$JAVA_OPTS -Dcom.sun.management.jmxremote"
# export JAVA_OPTS="$JAVA_OPTS -Dcom.sun.management.jmxremote.port=9999"
# export JAVA_OPTS="$JAVA_OPTS -Dcom.sun.management.jmxremote.ssl=false"
# export JAVA_OPTS="$JAVA_OPTS -Dcom.sun.management.jmxremote.authenticate=false"

# 디버그 모드 (개발환경 전용)
# export JAVA_OPTS="$JAVA_OPTS -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
