#!/usr/bin/env bash
#
# setenv.sh - Tomcat 환경 설정 (ICR 솔루션용)
# - install-core.sh 에 의해 템플릿에서 생성됨
#

# ──────────────────────────────────────────────
# 1. Java 홈 / PATH
# ──────────────────────────────────────────────
export JAVA_HOME=/usr/lib/jvm/temurin-21
export PATH="$JAVA_HOME/bin:$PATH"

# ──────────────────────────────────────────────
# 2. catalina.out 비활성화
# ──────────────────────────────────────────────
export CATALINA_OUT=/dev/null

# ──────────────────────────────────────────────
# 3. JVM 메모리 / 인코딩 / 타임존
# ──────────────────────────────────────────────
export JAVA_OPTS="$JAVA_OPTS -Xms@JVM_XMS@ -Xmx@JVM_XMX@"
export JAVA_OPTS="$JAVA_OPTS -Dfile.encoding=@JVM_ENCODING@"
export JAVA_OPTS="$JAVA_OPTS -Duser.timezone=@JVM_TIMEZONE@"

# ──────────────────────────────────────────────
# 4. Spring Profile / 사이트 식별자
# ──────────────────────────────────────────────
export JAVA_OPTS="$JAVA_OPTS -Dspring.profiles.active=@ENV@"
export JAVA_OPTS="$JAVA_OPTS -Dicr.site=@SITE@"

# ──────────────────────────────────────────────
# 5. 외부 설정 디렉토리
# ──────────────────────────────────────────────
export ICR_CONFIG_DIR="@ICR_CONFIG_DIR@"
export JAVA_OPTS="$JAVA_OPTS -Dicr.config.dir=${ICR_CONFIG_DIR}"

# ──────────────────────────────────────────────
# 6. Jasypt 복호화 키 (외부 yml 미사용)
# ──────────────────────────────────────────────
export JAVA_OPTS="$JAVA_OPTS -Djasypt.encryptor.password=@JASYPT_ENCRYPTOR_PASSWORD@"

# ──────────────────────────────────────────────
# 7. 추가 JVM 옵션 훅
# ──────────────────────────────────────────────
# 예:
# export JAVA_OPTS="$JAVA_OPTS -XX:+UseG1GC"

