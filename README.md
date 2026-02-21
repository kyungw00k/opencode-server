# opencode-server

`opencode-server`는 OpenCode 기반의 로컬/원격 개발 서버를 Docker로 운영하기 위한 프로젝트입니다.

핵심 목표:
- OpenCode 서버를 일관된 컨테이너 환경으로 실행
- AI provider(Z.AI), MCP, 플러그인, 개발 런타임을 한 번에 구성
- `docker compose` 이미지 실행과 GHCR 이미지 publish를 지원

## What It Includes

- OpenCode + Z.AI 모델 설정 (`config/opencode.json`)
- MCP 서버:
  - Playwright (headless Chromium)
  - GitHub MCP (`gh mcp-server`)
- 플러그인:
  - `oh-my-opencode`
  - `opencode-agent-memory`
  - `opencode-agent-skills`
  - `@franlol/opencode-md-table-formatter@0.0.3`
  - `opencode-worktree`
- 개발 도구/런타임:
  - Go, Rust, Python(+uv), Node.js, Bun, Kotlin
  - GitHub CLI, OpenSpec, OCX
- 부트스트랩:
  - `entrypoint.sh`에서 OpenCode config 초기화
  - 선택적으로 SSH 키/known_hosts 세팅
  - 선택적으로 OCX background agents 설치

## Repository Layout

- `Dockerfile`: 런타임 및 도구 설치
- `docker-compose.yaml`: GHCR 이미지 기반 실행
- `config/opencode.json`: OpenCode provider/MCP/plugin 설정
- `entrypoint.sh`: 부트스트랩 로직
- `.github/workflows/publish-ghcr.yaml`: GHCR 이미지 publish

## Quick Start

필수:
- Docker / Docker Compose
- `.env`에 API 토큰과 볼륨 경로 설정

실행 방법:

```bash
docker compose pull
docker compose up -d
```

## Always-On 운영 포인트

- 현재 compose 설정은 `restart: unless-stopped`로 재부팅 후 자동 복구됩니다.
- NAS/VM에서 외부 접속을 열 때는 리버스 프록시 + 인증(예: SSO, basic auth) + IP 제한을 함께 적용하세요.
- 실작업 성능/안정성을 위해 개발 소스는 VM 로컬 디스크를 우선 사용하고, NAS 공유는 백업/동기화 용도로 분리하는 구성을 권장합니다.

## GHCR Publish

빌드 관련 파일이 변경된 `main` 브랜치 push, `v*` 태그 push, 또는 수동 실행 시 GitHub Actions가 이미지를 GHCR로 push합니다.

- 워크플로: `.github/workflows/publish-ghcr.yaml`
- 기본 이미지명: `opencode-server`
- 태그: `latest`, `sha-*`, `v*`

## Security Notes

- `.env`는 비밀값을 포함하므로 커밋하지 않습니다.
- SSH 키는 이미지에 포함하지 않고, 호스트에서 read-only 마운트 후 부트스트랩 방식으로 사용합니다.
- 외부 노출 시 리버스 프록시 + 인증 + 네트워크 제한 구성을 권장합니다.
