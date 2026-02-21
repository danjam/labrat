# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Claude Code for Homelab — a Docker container bundling Claude Code + Yep Anywhere (web UI) for remote access to Claude Code from any device. Public repo; will eventually publish to GHCR.

## Build & Run

```bash
docker compose up -d --build        # Build and start
docker compose up -d --build --force-recreate  # Rebuild from scratch
docker compose logs -f               # Tail logs
docker compose down                  # Stop
docker compose down -v               # Stop and remove volumes (resets auth/sessions)
```

## Architecture

Single container, two main components sharing `/home/claude`:
- **Yep Anywhere** (Node.js web UI, port 3400) — manages Claude Code sessions as child processes
- **Claude Code** (native binary) — the AI coding assistant

The entrypoint (`entrypoint.sh`) runs as root to: resolve `_FILE` secrets from a whitelist, fix volume permissions via `chown`, check auth status, then drop to the `claude` user via `gosu` before exec'ing the CMD.

Key design decisions:
- **No `USER` directive in Dockerfile** — entrypoint must start as root for volume permission fixes
- **`gosu` not `sudo`** — purpose-built for Docker, no persistent privilege escalation
- **`debian:bookworm-slim`** base — smaller image, reduced attack surface
- **Whitelisted `_FILE` resolution** — only known secret vars are resolved, not arbitrary `*_FILE` env vars. Add new secrets to `SECRETS_WHITELIST` array in `entrypoint.sh`.

## Configuration

All operator config lives in the bind-mounted `./workspace/` directory:
- `workspace/CLAUDE.md.example` — starter instructions (user copies to `workspace/CLAUDE.md`)
- `workspace/.mcp.json.example` — starter MCP config (user copies to `workspace/.mcp.json`)
- `.env` — API keys and port config (not committed)

The `claude-home` named volume persists auth state and session history at `/home/claude`.

## Key Files

- `Dockerfile` — container image definition
- `entrypoint.sh` — secrets resolution, permission fixes, auth detection, privilege drop
- `compose.yaml` — local build + run config
- `.github/workflows/build.yml` — GHCR publish workflow (for later)
