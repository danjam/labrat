# Continue: Labrat Session Handover

## What This Project Is

Labrat = Docker container bundling Claude Code with Yep Anywhere (web UI) for homelab remote access. Gemini is available as an MCP server tool, not a standalone CLI. Repo: `github.com/danjam/labrat`.

## Current State

**Working.** Deployed on orac at `https://labrat.dannyjames.net` using GHCR image (`ghcr.io/danjam/labrat:latest`). MCP servers (Context7, Brave, Gemini, SSH) all functional. Claude Code sessions running from correct workspace directory.

### What Changed Recently

- **Gemini CLI removed** (`3492d09`) — free tier couldn't reliably access models. Gemini is now available only as an MCP server via `workspace/.mcp.json`.
- **Gemini MCP added to `.mcp.json.example`** (`7fc04b4`) — uses `github:danjam/mcp-server-gemini`, requires `GEMINI_API_KEY`.
- **Workspace example files fleshed out** (`ffc3e2d`) — `CLAUDE.md.example` and `.mcp.json.example` now have generic homelab templates.
- **Claude Code plugins installed via entrypoint** (`fb15216`) — installs `claude-md-management`, `code-review`, `commit-commands`, `pr-review-toolkit`, `ralph-loop` into `workspace/.claude/settings.json` on every boot (idempotent).
- **Documentation fixes** — README, CLAUDE.md, CONTINUE.md corrected for accuracy (Gemini, plugin install, auto-copy behavior, entrypoint steps).
- **PUID/PGID support** — runtime UID/GID matching via LinuxServer.io convention, works with pre-built GHCR images.
- **Build hardening** — npm cache clean, unset `_FILE` env vars after secret resolution, skip recursive chown when ownership matches, improved healthcheck.
- **`init: true`** added to compose.yaml for zombie process reaping.
- **MIT license** added, logo moved to `assets/`.
- **OCI labels** — added license and vendor to Dockerfile.

## The Workspace Project Problem (SOLVED)

### The Problem

Yep Anywhere always started Claude Code sessions in `/home/labrat` instead of `/home/labrat/workspace`. This meant `.mcp.json` and `CLAUDE.md` (in the bind-mounted workspace) were never found.

### Root Cause (traced through Yep Anywhere source code)

1. **Scanner fallback:** `scanner.js:190-206` — when no projects exist, falls back to `os.homedir()` (`/home/labrat`)
2. **Self-reinforcing loop:** `/home/labrat` gets most recent activity → sorts to `projects[0]` → client selects it → new sessions go there → activity updates → repeat
3. **Client-side selection:** `explicitSelection ?? cachedProject ?? projects[0].id` — the frontend always picks the most recent project
4. **No server-side config:** No env var or API exists to set a default project path

### What Works Now (on orac)

We did a complete clean slate: deleted all projects in `~/.claude/projects/`, deleted all Yep Anywhere data in `~/.yep-anywhere/` (except auth/install/vapid), then ran `docker exec -u labrat -it labrat-yep-1 claude` to create a real session as the `labrat` user from `/home/labrat/workspace` (the WORKDIR). This seeded `-home-labrat-workspace` as the most recent project. Yep Anywhere then picked it up and all subsequent sessions use the workspace.

### What Still Needs Fixing: Fresh Deploys

On a brand new deployment (fresh volume), the first session is the OAuth `/login` flow via Yep Anywhere. At that point no projects exist, so the scanner falls back to `homedir()` and creates `-home-labrat`. The workspace project never gets established.

**Fix implemented and verified:** The entrypoint creates `~/.claude/projects/-home-labrat-workspace/seed.jsonl` (no dot prefix — some globs skip dotfiles) containing `{"cwd":"/home/labrat/workspace"}`. Tested with `docker compose down -v` full clean start — workspace project is picked up correctly on first boot.

**If the seed doesn't work:** The fallback is to add symlinks in the entrypoint (`ln -sf /home/labrat/workspace/.mcp.json /home/labrat/.mcp.json` etc.) plus a `.claudeignore` at `/home/labrat/` to prevent context pollution. Less clean but guaranteed to work.

### Key Source Files (Yep Anywhere)

| File | What it does |
|------|-------------|
| `dist/projects/scanner.js:190-206` | Homedir fallback when no projects found |
| `dist/routes/projects.js:164-173` | GET /api/projects sorts by lastActivity |
| `dist/supervisor/Supervisor.js:~57` | Passes project.path as cwd to Claude SDK |
| `client-dist/assets/index-*.js` | Client project selection (minified) |

## Important: Exec Into Container

Always use the `labrat` user when exec'ing into the container:
```bash
docker exec -u labrat -it labrat-yep-1 claude
```
Running as root (the default) creates projects/sessions under `/root/.claude/` instead of `/home/labrat/.claude/`, which Yep Anywhere never sees.

## Known Quirks

**Post-login delay:** After completing `/login` for OAuth, Claude Code may briefly respond with "Not logged in" for a few seconds. Documented in README.

**`Binary envelope rejected: hasKey=false` warnings:** Harmless noise in logs. Yep Anywhere's WS relay checking for encrypted envelopes in local mode. No action needed.

**`/tmp/mcp_ssh_session_logs/` permissions:** If anything creates this directory as root (e.g., `docker exec` without `-u labrat`), the `mcp-ssh-session` MCP server will fail with a permission error. Fix: `chown -R labrat:labrat /tmp/mcp_ssh_session_logs/`. This only happens from manual `docker exec` as root — on a clean install the directory is created by Claude Code running as `labrat`, so no entrypoint fix needed.

**SSH keys:** Solved by mounting host keys read-only via `${HOME}/.ssh:/home/labrat/.ssh:ro` in `compose.override.yaml`. Docker's default bridge network can reach Tailscale IPs on the host, so no host networking needed.

## Architecture

- **Base image:** `debian:bookworm-slim`
- **Components:** Claude Code (native binary at `/usr/local/bin/claude`), Yep Anywhere (npm global), Node.js 22, Python 3 + uv, gh CLI, tmux; Gemini available via MCP server (not a local CLI)
- **Entrypoint runs as root:** resolves `_FILE` secrets, copies `.example` files, fixes volume permissions, bootstraps Claude Code onboarding, seeds workspace project, installs Claude Code plugins, sets up Yep Anywhere auth, shows agent auth status, drops to `labrat` user via `gosu`
- **Named volume `labrat-data`** at `/home/labrat` — persists auth, sessions, Yep Anywhere data
- **Bind mount `./workspace`** — operator config (`CLAUDE.md`, `.mcp.json`)
- **GHCR image:** `ghcr.io/danjam/labrat:latest` — auto-rebuilds on upstream version changes (checked every 6h via GitHub Releases API)
- **CMD:** `yepanywhere --host 0.0.0.0`

## Homelab Deployment (orac)

- Server: `danjam@orac` (no passwordless sudo)
- Stack: `/opt/stacks/labrat/`
- Domain: `labrat.dannyjames.net`
- Traefik reverse proxy with Cloudflare DNS challenge
- `compose.override.yaml` has `image: ghcr.io/danjam/labrat:latest` + Traefik labels + SSH key mount (`${HOME}/.ssh:/home/labrat/.ssh:ro`)
- `.env` has: `YEP_PASSWORD=pick-a-password`, `ALLOWED_HOSTS=labrat.dannyjames.net`, MCP API keys, `GITHUB_TOKEN`
- User authenticates Claude via `CLAUDE_CODE_OAUTH_TOKEN` (Max plan) or `/login` flow, NOT API key

## Key Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Image definition + OCI labels |
| `entrypoint.sh` | Secrets, `.example` copy, permissions, onboarding bootstrap, workspace seed, plugin install, Yep auth setup, privilege drop |
| `compose.yaml` | Base compose (build, volumes, env vars) |
| `compose.override.yaml` | Deployment-specific (Traefik labels, GHCR image) — gitignored |
| `.env.example` | Template for env vars |
| `workspace/CLAUDE.md.example` | Starter Claude Code instructions |
| `workspace/.mcp.json.example` | Starter MCP config (Context7, Brave, Gemini, SSH) |
| `.github/workflows/build.yml` | GHCR version check (every 6h) + conditional build |

## What's Left To Do

See `docs/TODO.md` for current tasks.
