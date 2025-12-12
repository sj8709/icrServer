# ICR 솔루션 Tomcat 설치 · 운영 자동화 가이드

## 0. 개요

본 문서는 ICR 솔루션을 Tomcat 기반으로 설치·운영하기 위한 표준 자동화 스크립트 사용 가이드이다.

### 설계 목표

- systemd 권한 없이 bin 기반 운영
- 사이트별 설정은 `site.conf` 단일 파일로 관리
- 설치 / 제거 / 기동 / 중지 / 배포 / 점검 / 헬스체크 역할 분리
- 운영 중 안전한 WAR 재배포 및 롤백 가능

### 대상 환경

- 금융권 / 폐쇄망 환경
- systemd 권한이 없는 서버
- 운영자 실수 최소화가 필요한 환경

---

## 1. 디렉토리 구조

```
icr-solution/
├── install.sh                 # 설치 진입점 (래퍼)
├── uninstall.sh               # 제거 진입점 (래퍼)
├── setup-permissions.sh       # 실행 권한 복구 스크립트
├── README.md
├── packages/
│   ├── apache-tomcat-*.tar.gz # Tomcat 배포판 (버전별 복수 가능)
│   ├── JDK21_x64.tar.gz       # 번들 JDK (Intel/AMD, JAVA_SOURCE=bundled 시 필요)
│   ├── JDK21_arm.tar.gz       # 번들 JDK (ARM64, JAVA_SOURCE=bundled 시 필요)
│   └── icr.war                # 애플리케이션 WAR
└── solution/
    ├── bin/
    │   ├── install-core.sh    # 설치 코어 로직
    │   ├── uninstall-core.sh  # 제거 코어 로직
    │   ├── start.sh           # 서비스 시작
    │   ├── stop.sh            # 서비스 중지
    │   ├── deploy-war.sh      # WAR 재배포
    │   ├── check.sh           # 종합 점검
    │   ├── health.sh          # HTTP 헬스체크
    │   └── health-https.sh    # HTTPS 헬스체크
    ├── config/
    │   └── site.conf          # 사이트별 설정 파일
    ├── modules/
    │   └── service_control.sh # 공통 서비스 제어 모듈
    └── templates/
        └── tomcat/
            ├── server.xml.tpl
            ├── context.xml.tpl
            ├── web.xml.tpl
            └── setenv.sh.tpl
```

### 설치 후 생성되는 디렉토리

```
/opt/icr-solution/              # INSTALL_BASE
├── tomcat -> apache-tomcat-*   # Tomcat 심볼릭 링크
├── apache-tomcat-10.1.50/      # 실제 Tomcat 디렉토리
│   ├── icr-webapps/
│   │   └── ROOT/               # 압축 해제된 WAR
│   └── logs/
├── java -> jdk-21.0.9+10       # Java 심볼릭 링크 (JAVA_SOURCE=bundled 시)
├── jdk-21.0.9+10/              # 번들 JDK 디렉토리 (JAVA_SOURCE=bundled 시)
├── config/
│   └── tomcat/                 # 생성된 설정 파일들
│       ├── server.xml
│       ├── context.xml
│       ├── web.xml
│       └── setenv.sh
├── logs/
├── data/
└── backup/
    └── war/                    # WAR 백업 파일들
```

> **참고**: `JAVA_SOURCE=bundled` 설정 시 `java/`, `jdk-21.0.9+10/` 디렉토리가 생성됩니다. `JAVA_SOURCE=system` 사용 시에는 생성되지 않습니다.

---

## 2. site.conf (사이트 설정)

모든 환경 설정은 단일 파일로 관리한다.

```
solution/config/site.conf
```

### 필수 설정

| 변수 | 설명 | 예시 |
|------|------|------|
| `SITE` | 사이트 식별자 | `INFODEA` |
| `ENV` | 환경 프로파일 (Spring) | `dev`, `prod-web`, `prod-batch` |
| `JAVA_SOURCE` | Java 소스 선택 | `system`, `bundled` |
| `JAVA_HOME` | Java 설치 경로 (JAVA_SOURCE=system 시 필수) | `/usr/lib/jvm/temurin-21` |
| `INSTALL_BASE` | 설치 기본 경로 | `/opt/icr-solution` |
| `TOMCAT_DIST_NAME` | Tomcat 배포판 이름 | `apache-tomcat-10.1.50` |
| `TOMCAT_HOME` | Tomcat 심볼릭 링크 경로 | `/opt/icr-solution/tomcat` |
| `WAS_HTTP_PORT` | HTTP 포트 | `28080` |
| `WAS_APP_BASE` | 앱 배포 디렉토리 (상대경로) | `icr-webapps` |
| `JASYPT_ENCRYPTOR_PASSWORD` | Jasypt 복호화 키 | `********` |

#### Java 설정 방식

**1. 시스템 Java 사용 (JAVA_SOURCE=system)**

시스템에 설치된 JDK를 사용한다. `JAVA_HOME` 설정 필수.

```bash
JAVA_SOURCE=system
JAVA_HOME=/usr/lib/jvm/temurin-21
```

> 일반적인 경로 예시:
> - RHEL/CentOS: `/usr/lib/jvm/java-21-openjdk`
> - Ubuntu/Debian: `/usr/lib/jvm/java-21-openjdk-amd64`
> - Eclipse Temurin: `/usr/lib/jvm/temurin-21`
> - Amazon Corretto: `/usr/lib/jvm/java-21-amazon-corretto`

**2. 번들 Java 사용 (JAVA_SOURCE=bundled)**

패키지에 포함된 JDK를 자동 설치한다. 폐쇄망 환경에서 권장.

```bash
JAVA_SOURCE=bundled
# JAVA_HOME은 자동 설정됨 (설정값 무시)
```

- 아키텍처 자동 감지 (x64/arm64)
- 필요 파일: `packages/JDK21_x64.tar.gz` 또는 `packages/JDK21_arm.tar.gz`
- 설치 위치: `$INSTALL_BASE/java` -> `$INSTALL_BASE/jdk-21.0.9+10`

### 선택 설정

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `WAS_SHUTDOWN_PORT` | Tomcat Shutdown 포트 | `8005` |
| `WAS_HTTPS_PORT` | HTTPS 포트 | `28443` |
| `WAS_ENABLE_HTTPS` | HTTPS 커넥터 활성화 | `N` |
| `WAS_SSL_KEYSTORE_FILE` | SSL 인증서 파일명 | `localhost-rsa.jks` |
| `WAS_SSL_KEYSTORE_PASSWORD` | SSL 인증서 비밀번호 | `changeit` |
| `JVM_XMS` | JVM 초기 힙 | `512m` |
| `JVM_XMX` | JVM 최대 힙 | `1024m` |
| `JVM_TIMEZONE` | JVM 타임존 | `Asia/Seoul` |
| `JVM_ENCODING` | JVM 인코딩 | `UTF-8` |
| `ICR_CONFIG_DIR` | 외부 설정 디렉토리 | `${INSTALL_BASE}/config` |

> **참고**: `WAS_SHUTDOWN_PORT`는 동일 서버에 다중 Tomcat 인스턴스를 운영할 때 충돌 방지를 위해 인스턴스별로 다르게 설정해야 한다.

### SSL/TLS 인증서 설정 (HTTPS 사용 시)

`WAS_ENABLE_HTTPS=Y`일 때 SSL 인증서 설정이 필요하다.

| 변수 | 설명 | 비고 |
|------|------|------|
| `WAS_SSL_KEYSTORE_FILE` | 인증서 파일명 | `TOMCAT_HOME/conf/` 기준 |
| `WAS_SSL_KEYSTORE_PASSWORD` | 인증서 비밀번호 | - |

**설치 시 검증**:
- 인증서 파일이 없으면 설치 중단
- 기본값(`localhost-rsa.jks` + `changeit`) 사용 시 경고 출력

> **운영환경 주의**: 기본 샘플 인증서는 테스트용이므로, 운영환경에서는 반드시 실제 인증서로 교체해야 한다.

### 서비스 제어 설정

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `SVC_START_TIMEOUT_SEC` | 시작 대기 시간(초) | `30` |
| `SVC_STOP_TIMEOUT_SEC` | 중지 대기 시간(초) | `30` |
| `SVC_STOP_FORCEKILL` | 타임아웃 시 강제 종료 | `Y` |
| `SVC_STOP_FORCEKILL_GRACE_SEC` | 강제 종료 후 대기(초) | `1` |

---

## 3. 설치

### 최초 설치

```bash
./install.sh
```

### 설정 파일 강제 재생성

```bash
ICR_FORCE_REGEN=Y ./install.sh
```

### 설치 시 수행 내용

1. `site.conf` 로드 및 검증
2. `INSTALL_BASE` 디렉토리 구조 생성
3. Tomcat 압축 해제 및 심볼릭 링크 설정
4. SSL 인증서 검증 (HTTPS 활성화 시)
5. 템플릿에서 설정 파일 생성 (`server.xml`, `context.xml`, `web.xml`, `setenv.sh`)
6. Tomcat conf/bin에 설정 파일 심볼릭 링크
7. WAR 초기 배포
8. 스크립트 실행 권한 설정 (`chmod +x`)

### Windows에서 작업 후 권한 복구

Windows에서 파일을 수정한 후 Linux로 복사하면 실행 권한이 사라질 수 있다.
이 경우 다음 스크립트를 실행하여 권한을 복구한다.

```bash
# 방법 1: bash로 직접 실행
bash setup-permissions.sh

# 방법 2: 권한 부여 후 실행
chmod +x setup-permissions.sh && ./setup-permissions.sh
```

> **참고**: `install.sh` 실행 시에도 모든 스크립트의 실행 권한이 자동으로 설정된다.

---

## 4. 제거 (uninstall)

### 기본 제거 (Tomcat만 삭제, 설정/데이터 유지)

```bash
./uninstall.sh
```

### 전체 제거 (INSTALL_BASE 통째 삭제)

```bash
./uninstall.sh --full
```

### 제거 대상 미리 확인

```bash
./uninstall.sh --dry-run
```

### 확인 프롬프트 스킵

```bash
./uninstall.sh --force
```

### 옵션 조합

```bash
# 전체 삭제 + 확인 스킵 + 미리보기
./uninstall.sh --full --force --dry-run
```

### 제거 범위

| 모드 | 삭제 대상 | 유지 대상 |
|------|----------|----------|
| 기본 | `tomcat` 심볼릭 링크, 실제 Tomcat 디렉토리 | `config/`, `logs/`, `data/`, `backup/` |
| `--full` | `INSTALL_BASE` 전체 | 없음 |

---

## 5. 서비스 기동 / 중지

### 기동

```bash
solution/bin/start.sh
```

### 중지

```bash
solution/bin/stop.sh
```

### 특징

- systemd 미사용
- Tomcat `startup.sh` / `shutdown.sh` 기반 동작
- 타임아웃 후 강제 종료 지원 (`SVC_STOP_FORCEKILL=Y`)

---

## 6. WAR 재배포 (deploy-war.sh)

### 기본 재배포 (중지 → 배포 → 기동)

```bash
solution/bin/deploy-war.sh
```

### 기동 없이 WAR만 교체

```bash
solution/bin/deploy-war.sh --no-restart
```

### 배포 후 서비스 응답 확인 포함

```bash
solution/bin/deploy-war.sh --wait-health --health-path /icr/login
```

### 외부 WAR 파일 지정

```bash
solution/bin/deploy-war.sh --war /path/to/new-icr.war
```

### DRY RUN

```bash
solution/bin/deploy-war.sh --dry-run
```

### 전체 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--war <path>` | 배포할 WAR 파일 경로 | `packages/icr.war` |
| `--restart` | 재기동 수행 | (기본값) |
| `--no-restart` | 재기동 안 함 | - |
| `--keep <N>` | 백업 보관 개수 | `20` |
| `--wait-health` | 배포 후 헬스체크 수행 | OFF |
| `--health-path <p>` | 헬스체크 경로 | `/icr/login` |
| `--health-retry <N>` | 헬스체크 재시도 횟수 | `5` |
| `--health-interval <s>` | 재시도 간격(초) | `2` |
| `--check-https` | HTTPS 헬스체크 추가 수행 | OFF |
| `--dry-run` | 실제 실행 없이 계획만 출력 | - |

### 백업 정책

- 기존 WAR는 `${INSTALL_BASE}/backup/war/icr.war.YYYYMMDD_HHMMSS` 로 백업
- 기본 20개 유지, `--keep` 옵션으로 조정 가능

---

## 7. 운영 점검 (check.sh)

### 기본 점검

```bash
solution/bin/check.sh
```

### 서비스 응답 포함 점검

```bash
solution/bin/check.sh --with-health --health-path /icr/login
```

### 최근 로그 확인

```bash
solution/bin/check.sh --tail 200
```

### 점검 항목

1. Tomcat `RUNNING` / `STOPPED` 상태
2. Java 프로세스 요약
3. 포트 리슨 상태 (HTTP/HTTPS)
4. WAR 파일 존재 여부
5. (옵션) 서비스 응답 확인
6. (옵션) `catalina.out` 최근 로그

### 전체 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--with-health` | 헬스체크 수행 | OFF |
| `--health-path <path>` | 헬스체크 경로 | `/icr/login` |
| `--health-retry <N>` | 재시도 횟수 | `3` |
| `--health-interval <s>` | 재시도 간격(초) | `1` |
| `--tail <N>` | catalina.out 출력 줄 수 | `0` (안 함) |
| `--dry-run` | DRY RUN | - |

> **참고**: `check.sh`는 정보 출력용이며 exit code는 항상 0이다.

---

## 8. 헬스체크 (health.sh / health-https.sh)

### HTTP 헬스체크

```bash
solution/bin/health.sh
```

### 경로 지정

```bash
solution/bin/health.sh --path /icr/login
```

### HTTPS 헬스체크

```bash
solution/bin/health-https.sh
```

### 인증서 검증 활성화 (기본은 `-k` 옵션으로 검증 OFF)

```bash
solution/bin/health-https.sh --verify
```

### 전체 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--path <path>` | 체크 경로 | `/icr/login` |
| `--timeout <sec>` | curl 타임아웃 | `5` |
| `--retry <N>` | 재시도 횟수 | `3` |
| `--interval <sec>` | 재시도 간격(초) | `1` |
| `--verbose` | 실패 시 응답 헤더 출력 | OFF |
| `--verify` | TLS 인증서 검증 (HTTPS만) | OFF |
| `--dry-run` | DRY RUN | - |

### 응답 코드 판정

| HTTP 코드 | 판정 |
|-----------|------|
| `200`, `301`, `302`, `303`, `307`, `308` | 정상 |
| `401`, `403` | 정상 (인증 필요 페이지) |
| `000` | WARMING UP (포트/앱 기동 중) |
| 기타 | FAIL |

---

## 9. 장애 판단 기준

| check.sh | health.sh | 의미 |
|----------|-----------|------|
| FAIL | FAIL | Tomcat 장애 |
| OK | FAIL | 애플리케이션 문제 |
| OK | OK | 정상 |
| OK | WARMING UP | 기동 중 |

---

## 10. 로그 / 데이터 경로

```
/opt/icr-solution/
├── tomcat/
│   └── logs/
│       └── catalina.out       # Tomcat 메인 로그
├── backup/
│   └── war/                   # WAR 백업 (timestamp별)
├── config/
│   └── tomcat/                # 생성된 Tomcat 설정
├── logs/                      # 솔루션 로그 (예약)
└── data/                      # 애플리케이션 데이터 (예약)
```

---

## 11. 운영 권장 흐름

### 평상시 점검

```bash
solution/bin/check.sh
```

### 배포

```bash
solution/bin/deploy-war.sh --wait-health --health-path /icr/login
```

### 장애 발생 시

```bash
solution/bin/check.sh
solution/bin/health.sh
tail -f /opt/icr-solution/tomcat/logs/catalina.out
```

### 재설치 (설정 유지)

```bash
./uninstall.sh
./install.sh
```

### 완전 초기화

```bash
./uninstall.sh --full --force
./install.sh
```

---

## 12. 스크립트 요약

| 스크립트 | 역할 | 주요 옵션 |
|----------|------|----------|
| `install.sh` | 설치 진입점 | `ICR_FORCE_REGEN=Y` |
| `uninstall.sh` | 제거 진입점 | `--full`, `--force`, `--dry-run` |
| `setup-permissions.sh` | 실행 권한 복구 | - |
| `start.sh` | 서비스 시작 | - |
| `stop.sh` | 서비스 중지 | - |
| `deploy-war.sh` | WAR 재배포 | `--war`, `--no-restart`, `--wait-health` |
| `check.sh` | 종합 점검 | `--with-health`, `--tail` |
| `health.sh` | HTTP 헬스체크 | `--path`, `--retry` |
| `health-https.sh` | HTTPS 헬스체크 | `--path`, `--verify` |

---

## 13. 주의사항

1. **각 스크립트는 역할이 명확히 분리**되어 있으며, 혼용 사용을 권장하지 않는다.
2. `site.conf` 수정 후에는 **재설치**(`./uninstall.sh && ./install.sh`) 또는 **설정 강제 재생성**(`ICR_FORCE_REGEN=Y ./install.sh`)이 필요하다.
3. `uninstall.sh` 기본 모드는 **설정/데이터를 유지**하므로, 재설치 시 기존 설정이 재사용된다.
4. 운영 중 WAR 교체는 반드시 `deploy-war.sh`를 사용한다. (백업 + 롤백 가능) 
