# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository sets up a self-hosted OpenCode server on a Synology DS918+ NAS using Docker Compose (Container Manager). The server uses Z.AI as the AI provider (GLM models) and includes development tooling for full-stack development.

## Final Outputs

- `docker-compose.yaml` - Main container definition for Synology Container Manager
- `.env` - Environment variables (credentials, paths, ports)

## Architecture

The stack is a single container based on Ubuntu with:
- **OpenCode** - AI coding agent serving as the development interface
- **Z.AI Provider** - GLM models via Z.AI API (configured in `opencode.json`)
- **OpenSpec** - Spec-driven development (SDD) framework for AI coding
- **OCX CLI** - OpenCode extension manager (registry + component install)
- **MCP servers** - Browser control (Playwright, headless Google Chrome) and GitHub CLI integration
- **Runtimes** - Go, Rust, Python 3, Bun, Node.js, Kotlin pre-installed

## Key Configuration Files (inside container)

| Path | Purpose |
|------|---------|
| `/home/opencode/.config/opencode/opencode.json` | OpenCode provider, MCP, agent config |
| `/home/opencode/.local/share/opencode/auth.json` | Auth tokens (mounted from NAS host) |

## opencode.json Structure

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "z-ai": {
      "name": "Z.AI",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://api.z.ai/v1"
      },
      "models": {
        "glm-4-plus": { "name": "GLM-4-Plus" },
        "glm-4.7": { "name": "GLM-4.7" }
      }
    }
  },
  "model": "z-ai/glm-4.7",
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "@playwright/mcp@latest"],
      "enabled": true
    },
    "github": {
      "type": "local",
      "command": ["gh", "mcp-server"],
      "enabled": true,
      "env": { "GH_TOKEN": "{env:GH_TOKEN}" }
    }
  }
}
```

## Synology Container Manager Notes

- Uses `docker-compose.yaml` project format (Container Manager → Project)
- Volume paths use Synology NAS absolute paths (e.g., `/volume1/...`)
- Container runs as non-root user (`opencode` uid 1000)
- `restart: unless-stopped` for persistence across reboots
- Terminal access via `docker exec -it opencode-server opencode` or Container Manager terminal
- SSH keys should be mounted from host (read-only) instead of baked into image

## GHCR Publish Workflow

- GitHub Actions workflow: `.github/workflows/publish-ghcr.yaml`
- Trigger: build-related file changes on `main`, tag push (`v*`), or manual `workflow_dispatch`
- Push target: `ghcr.io/<owner>/<image>` (default image name `opencode-server`, override via repository variable `GHCR_IMAGE_NAME`)
- Build platform: `linux/amd64` (compatible with DS918+)

## Plugins

OpenCode auto-installs plugins at startup via Bun. Binaries are cached in `~/.cache/opencode` (NAS-mounted to survive rebuilds).

| Plugin | Purpose |
|--------|---------|
| `oh-my-opencode` | Multi-agent orchestration, specialized agents (Oracle, Librarian, frontend), hooks, workflows |
| `opencode-agent-memory` | Letta-style persistent memory blocks across sessions; tools: `memory_list`, `memory_set`, `memory_replace` |
| `opencode-agent-skills` | Dynamic skill loading; injects `<available-skills>` on session start, re-injects after compaction |
| `@franlol/opencode-md-table-formatter@0.0.3` | Auto-formats markdown tables while editing docs and specs |
| `opencode-worktree` | Git worktree workflows for parallel task branches |

In addition to npm-based plugins above, the container bootstraps `kdco/background-agents` through OCX at startup (writes to `/workspace/.opencode/plugin`), controlled by `OCX_BOOTSTRAP` env vars.

For Git over SSH in container:
- Mount host SSH dir to `/home/opencode/.ssh-host:ro` (e.g. `${OPENCODE_SSH_PATH}`)
- Entrypoint copies selected key/config to `/home/opencode/.ssh` with strict permissions
- `GIT_USE_SSH_FOR_GITHUB=true` sets `git@github.com:` as default for GitHub remotes

**opencode-agent-skills:** set `OPENCODE_AGENT_SKILLS_SUPERPOWERS_MODE=true` to enable Superpowers workflow.

**Skill directories** (first match wins, project-level overrides user-level):
1. `.opencode/skills/` — per-project
2. `~/.opencode/skills/` — cross-project

Each skill = directory with `SKILL.md` (YAML frontmatter: `name`, `description` + agent instructions).

## Environment Variables

All secrets live in `.env` (never committed). Key variables:

| Variable | Description |
|----------|-------------|
| `ZAI_API_KEY` | Z.AI API key from https://z.ai/manage-apikey/apikey-list |
| `GH_TOKEN` | GitHub personal access token for gh CLI and MCP |
| `OPENCODE_DATA_PATH` | NAS path for persistent OpenCode data (auth, sessions) |
| `OPENCODE_CONFIG_PATH` | NAS path for opencode.json config |
| `OPENCODE_PLUGIN_CACHE_PATH` | NAS path for plugin cache (avoids re-downloading on restart) |
| `OPENCODE_WORKSPACE_PATH` | NAS path to mount as /workspace |
| `OPENCODE_PORT` | Port for OpenCode server (default: 3000) |
| `OPENCODE_SSH_PATH` | Host path to SSH directory for optional read-only mount |
| `SSH_BOOTSTRAP` | Enable SSH bootstrap at container start (`true`/`false`) |
| `SSH_SOURCE_DIR` | Mounted SSH source directory inside container |
| `SSH_PRIVATE_KEY_NAME` | Private key filename to copy (default: `id_ed25519`) |
| `SSH_ADD_GITHUB_KNOWN_HOSTS` | Auto-add github.com host keys using `ssh-keyscan` |
| `GIT_USE_SSH_FOR_GITHUB` | Rewrite GitHub HTTPS remotes to SSH for git operations |
| `OCX_BOOTSTRAP` | Enable automatic OCX bootstrap on container start (`true`/`false`) |
| `OCX_REGISTRY_URL` | OCX registry URL (default: `https://registry.kdco.dev`) |
| `OCX_REGISTRY_NAME` | OCX registry alias (default: `kdco`) |
| `OCX_BACKGROUND_COMPONENT` | Component installed on boot (default: `kdco/background-agents`) |

## First Run Setup

`entrypoint.sh` auto-copies `opencode.json.template` → mounted config volume if `opencode.json` is not present. NAS directories must exist before first `docker-compose up`:

```bash
mkdir -p /volume1/docker/opencode/{data,config,plugin-cache}
```

## Runtime Versions (in container)

Installed via official methods in Dockerfile:
- Go (latest stable via official tarball)
- Rust (via rustup)
- Python 3 + pip + uv
- Node.js LTS + npm (via nvm or official repo)
- Bun (via official installer)
- Kotlin + JDK (via SDKMAN or official package)
- GitHub CLI (gh)
- Playwright (via npx, chromium dependencies included)
- OpenSpec (`@fission-ai/openspec`, global npm package)
- OCX (`ocx`, global npm package)

## OpenSpec Workflow

OpenSpec is a spec-driven development (SDD) framework. Initialize it once per project, then use slash commands to drive feature development:

```bash
# In a project directory inside /workspace:
openspec init

# Then inside OpenCode chat:
/opsx:new <feature-name>   # Create new feature branch + spec folder
/opsx:ff                   # Generate proposal, specs, design, tasks docs
/opsx:apply                # Implement the planned tasks
/opsx:archive              # Archive completed work
```

Each feature gets an organized folder with: proposal, specification, design notes, and implementation checklist. Run `openspec init` per project — it requires Node.js 20.19+.


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

*No recent activity*
</claude-mem-context>
