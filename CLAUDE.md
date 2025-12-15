# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ICR 솔루션 Tomcat 설치·운영 자동화 패키지. 금융권/폐쇄망 환경에서 systemd 없이 bin 기반으로 Tomcat을 설치·운영한다.

## Key Commands

```bash
# 설치
./install.sh
ICR_FORCE_REGEN=Y ./install.sh    # 설정 강제 재생성

# 제거
./uninstall.sh                     # Tomcat만 삭제 (config/data 유지)
./uninstall.sh --full              # 전체 삭제
./uninstall.sh --dry-run           # 삭제 대상 미리보기

# 서비스 제어
solution/bin/start.sh
solution/bin/stop.sh

# WAR 배포
solution/bin/deploy-war.sh
solution/bin/deploy-war.sh --wait-health --health-path /icr/login

# 점검
solution/bin/check.sh
solution/bin/health.sh
solution/bin/health-https.sh

# Windows 작업 후 권한 복구
bash setup-permissions.sh
```

## Architecture

### Script Layer Pattern
- **래퍼 스크립트** (`install.sh`, `uninstall.sh`): 루트에 위치, `solution/bin/*-core.sh` 호출
- **코어 스크립트** (`solution/bin/*-core.sh`): 실제 로직 구현
- **공통 모듈** (`solution/modules/`):
  - `service_control.sh`: `svc_start()`, `svc_stop()`, `is_running()`, `load_site_conf()` 등 제공
  - `logging.sh`: `init_logging()`, `log()`, `die()` 제공 (스크립트 실행 로그)

### Configuration Flow
```
site.conf → install-core.sh → templates/*.tpl → INSTALL_BASE/config/tomcat/*
```
- `solution/config/site.conf`: 모든 환경 설정의 단일 진실 소스 (Single Source of Truth)
- `solution/templates/tomcat/*.tpl`: `@TOKEN@` 형식 플레이스홀더 치환
- 설치 시 `INSTALL_BASE/config/tomcat/`에 실제 설정 파일 생성 후 Tomcat conf/bin에 심볼릭 링크

### DRY_RUN Pattern
대부분의 스크립트가 `--dry-run` 옵션을 지원하며, `run()` 함수를 통해 실행:
```bash
run() {
  log "+ $*"
  if [[ "${DRY_RUN}" == "Y" ]]; then return 0; fi
  eval "$@"
}
```

### Directory Conventions
| 경로 | 용도 |
|------|------|
| `packages/` | Tomcat tgz, icr.war 원본 |
| `solution/bin/` | 실행 스크립트 |
| `solution/modules/` | 공통 bash 모듈 |
| `solution/templates/` | 설정 파일 템플릿 |
| `solution/config/` | site.conf |
| `solution/logs/` | 스크립트 실행 로그 |

### Installed Structure (INSTALL_BASE)
```
/opt/icr-solution/
├── tomcat -> apache-tomcat-*    # Tomcat 심볼릭 링크
├── java -> jdk-21.0.9+10        # Java 심볼릭 링크 (JAVA_SOURCE=bundled 시)
├── jdk-21.0.9+10/               # 번들 JDK (JAVA_SOURCE=bundled 시)
├── config/tomcat/               # 생성된 설정 파일
├── backup/war/                  # WAR 백업
├── logs/, data/                 # 예약 디렉토리
```

## Script Conventions

- 이모지 사용 금지 (Linux 터미널 호환성)
- 모든 스크립트는 `set -euo pipefail` 또는 `set -Eeuo pipefail` 사용
- `logging.sh` 모듈 사용: `log()`, `die()`, `init_logging()` 함수 제공
- 경로 계산: `SCRIPT_DIR → SOLUTION_HOME → BASE_DIR` 패턴
- 모듈 로딩 순서: `logging.sh` → `service_control.sh`
- 스크립트 실행 로그: `solution/logs/{스크립트명}-{YYYYMMDD}.log`

## site.conf Required Variables

| 변수 | 설명 |
|------|------|
| `SITE` | 사이트 식별자 |
| `ENV` | Spring 프로파일 |
| `JAVA_HOME` | Java 설치 경로 (사이트별 필수 확인) |
| `INSTALL_BASE` | 설치 기본 경로 |
| `TOMCAT_HOME` | Tomcat 심볼릭 링크 경로 |
| `WAS_SHUTDOWN_PORT` | Tomcat Shutdown 포트 (다중 인스턴스 시 변경) |
| `WAS_HTTP_PORT` | HTTP 포트 |
| `WAS_APP_BASE` | 앱 배포 디렉토리 (상대경로) |
| `WAS_SSL_KEYSTORE_FILE` | SSL 인증서 파일명 (HTTPS 사용 시) |
| `WAS_SSL_KEYSTORE_PASSWORD` | SSL 인증서 비밀번호 (HTTPS 사용 시) |
| `JASYPT_ENCRYPTOR_PASSWORD` | Jasypt 복호화 키 |

## Documentation Sync

코드 변경 시 아래 문서들을 항상 최신 상태로 유지해야 합니다.

| 문서 | 용도 | 갱신 시점 |
|------|------|----------|
| `CLAUDE.md` | Claude Code 가이드 | 아키텍처/스크립트 변경 시 |
| `docs/개발자_매뉴얼.md` | 개발자용 상세 가이드 | site.conf/템플릿/JVM 옵션 변경 시 |
| `docs/운영자_매뉴얼.md` | 운영자용 실행 가이드 | 설치/운영 절차 변경 시 |

**갱신 원칙:**
- 템플릿(*.tpl) 변경 → 개발자 매뉴얼 갱신
- 스크립트 옵션 변경 → 운영자 매뉴얼 갱신
- 디렉토리 구조 변경 → 모든 문서 갱신
