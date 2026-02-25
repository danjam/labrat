# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Labrat — a Docker container bundling Claude Code + Yep Anywhere (web UI) for homelab remote access. Public repo, published to GHCR at `ghcr.io/danjam/labrat`.

## Build & Run

```bash
# Pull-based (production)
docker compose pull && docker compose up -d

# Build from source (development)
docker compose up -d --build
docker compose up -d --build --force-recreate  # Rebuild from scratch

# Common
docker compose logs -f               # Tail logs
docker compose down                  # Stop
docker compose down -v               # Stop and remove volumes (resets auth/sessions)

# GHCR
gh workflow run build.yml             # Trigger manual GHCR build
gh run list --workflow=build.yml -L1  # Check build status
```

## Architecture

Single container, two main components sharing `/home/labrat`:
- **Yep Anywhere** (Node.js web UI, port 3400) — manages Claude Code sessions as child processes
- **Claude Code** (native binary) — Anthropic's AI coding assistant
- **Gemini** — available as an MCP server tool (configured in `workspace/.mcp.json`), not a local CLI

The entrypoint (`entrypoint.sh`) runs as root to: resolve `_FILE` secrets from a whitelist, copy `.example` starter config files, fix volume permissions via `chown`, bootstrap Claude Code onboarding, seed the workspace project, install Claude Code plugins, set up Yep Anywhere auth, check agent auth status, then drop to the `labrat` user via `gosu` before exec'ing the CMD.

Key design decisions:
- **No final `USER` directive in Dockerfile** — entrypoint must start as root for volume permission fixes
- **`gosu` not `sudo`** — purpose-built for Docker, no persistent privilege escalation
- **`debian:bookworm-slim`** base — smaller image, reduced attack surface
- **Whitelisted `_FILE` resolution** — only known secret vars are resolved, not arbitrary `*_FILE` env vars. Add new secrets to `SECRETS_WHITELIST` array in `entrypoint.sh`.

## GHCR

- Image: `ghcr.io/danjam/labrat`
- Automated version-check every 6 hours — rebuilds only when Claude Code or Yep Anywhere release a new version (detected via GitHub Releases API)
- Manual dispatch always triggers a build
- Pushing a `v*` tag also triggers a build and adds the tag to the image (e.g. `:v0.4.0`)
- Tags: `:latest` + version combo (`:claude-2.1.52-yep-0.4.3`)
- Version labels: `dev.labrat.claude-version`, `dev.labrat.yep-version` (set at build time, read by check job via `crane`)
- Upstream versions: `gh api repos/anthropics/claude-code/releases/latest` and `gh api repos/kzahel/yepanywhere/releases/latest`
- **Do not use** `claude.ai/cli/LATEST_VERSION` (Cloudflare-blocked) or `@anthropic-ai/claude-code` npm (deprecated)
- Workflow: `.github/workflows/build.yml`

## Configuration

All operator config lives in the bind-mounted `./workspace/` directory:
- `workspace/CLAUDE.md.example` — starter instructions for Claude Code (auto-copied to `workspace/CLAUDE.md` on first run if absent)
- `workspace/.mcp.json.example` — starter MCP config (auto-copied to `workspace/.mcp.json` on first run if absent)
- `.env` — API keys and port config (not committed)

Required env vars (see `.env.example`):
- `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` — Claude Code auth (or use `/login` OAuth flow)
- `YEP_PASSWORD` — Yep Anywhere login password
- `ALLOWED_HOSTS` — hostnames for reverse proxy access
- `GEMINI_API_KEY`, `BRAVE_API_KEY`, `CONTEXT7_API_KEY` — (optional) MCP server keys
- `GITHUB_TOKEN` — (optional) GitHub CLI auth

The `labrat-data` named volume persists auth state and session history at `/home/labrat`.

## Gotchas

- **Always exec as labrat:** `docker exec -u labrat -it <container> claude` — running as root creates sessions under `/root/.claude/` which Yep never sees
- **Volume overlays `/home/labrat`** — anything written there during build is hidden at runtime by the named volume. That's why the claude binary is copied to `/usr/local/bin/`.
- **PUID/PGID** — entrypoint supports LinuxServer.io-style `PUID`/`PGID` env vars for bind mount permission matching
- **`init: true`** — compose.yaml uses this to reap zombie processes from orphaned Claude Code sessions
- **First boot is slow** — plugin installation and Yep auth setup run on first start only

## Key Files

- `Dockerfile` — container image definition + OCI labels
- `entrypoint.sh` — secrets resolution, `.example` copy, permission fixes, onboarding bootstrap, workspace seed, plugin install, Yep auth setup, privilege drop
- `compose.yaml` — base compose (build + pull, volumes, env vars)
- `compose.override.yaml` — deployment-specific overrides (gitignored)
- `.github/workflows/build.yml` — GHCR version check (every 6h) + conditional build
- `.env.example` — template for environment variables
- `LICENSE` — MIT
- `docs/TODO.md` — task checklist
- `docs/PROGRESS.md` — project history and solved problems
