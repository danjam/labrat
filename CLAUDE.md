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
```

## Architecture

Single container, two main components sharing `/home/labrat`:
- **Yep Anywhere** (Node.js web UI, port 3400) — manages Claude Code sessions as child processes
- **Claude Code** (native binary) — Anthropic's AI coding assistant

The entrypoint (`entrypoint.sh`) runs as root to: resolve `_FILE` secrets from a whitelist, fix volume permissions via `chown`, bootstrap Claude Code onboarding, seed the workspace project, check agent auth status, then drop to the `labrat` user via `gosu` before exec'ing the CMD.

Key design decisions:
- **No `USER` directive in Dockerfile** — entrypoint must start as root for volume permission fixes
- **`gosu` not `sudo`** — purpose-built for Docker, no persistent privilege escalation
- **`debian:bookworm-slim`** base — smaller image, reduced attack surface
- **Whitelisted `_FILE` resolution** — only known secret vars are resolved, not arbitrary `*_FILE` env vars. Add new secrets to `SECRETS_WHITELIST` array in `entrypoint.sh`.

## GHCR

- Image: `ghcr.io/danjam/labrat`
- Weekly automated rebuilds (Mondays 06:00 UTC) + manual dispatch
- Tags: `:latest` + date-based (`:2026-02-21`)
- Workflow: `.github/workflows/build.yml`

## Configuration

All operator config lives in the bind-mounted `./workspace/` directory:
- `workspace/CLAUDE.md.example` — starter instructions for Claude Code (user copies to `workspace/CLAUDE.md`)
- `workspace/.mcp.json.example` — starter MCP config (user copies to `workspace/.mcp.json`)
- `.env` — API keys and port config (not committed)

The `labrat-data` named volume persists auth state and session history at `/home/labrat`.

## Key Files

- `Dockerfile` — container image definition + OCI labels
- `entrypoint.sh` — secrets resolution, permission fixes, onboarding bootstrap, workspace seed, auth detection, privilege drop
- `compose.yaml` — base compose (build + pull, volumes, env vars)
- `compose.override.yaml` — deployment-specific overrides (gitignored)
- `.github/workflows/build.yml` — GHCR publish (weekly + manual dispatch)
