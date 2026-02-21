# Claude Code for Homelab

## Project Overview

A Docker container that bundles **Claude Code** and **Yep Anywhere** into a single image for homelab use. Access Claude Code from any device via a web browser — phone, laptop, tablet — using Yep Anywhere as the interface.

The container exposes Yep Anywhere on a configurable port. All configuration — Claude Code project settings, MCP servers, API keys — lives in a single bind-mounted workspace directory that the operator controls from the host. Sensitive values support Docker's `_FILE` convention for file-based secrets.

## Architecture Decisions

### Why a single container?

Yep Anywhere reads Claude Code's session history from `~/.claude/`. They must share the same home directory. Splitting them into separate containers would require shared volumes and UID mapping for no benefit. Yep Anywhere is the entrypoint — it manages Claude Code sessions as child processes.

### Why a non-root user?

Security best practice. The `claude` user runs with minimal privileges. The home directory `/home/claude` is persisted via a named volume for auth state and session history. The entrypoint starts as root to fix volume ownership, then drops to the `claude` user via `gosu` before launching the application.

### Why Node.js and uv in the image?

Yep Anywhere is a Node.js application (requires `>=20`). Node.js 22 LTS is used as the current active LTS with support through April 2027. Most MCP servers are distributed via `npx` (Node) or `uvx` (Python/uv), so both runtimes are included.

### How is the workspace structured?

Claude Code's working directory is a **bind-mounted workspace** from the host. This is the single place the operator manages all project-level configuration:

```
./workspace/
├── CLAUDE.md        # Instructions and context for Claude Code
├── .mcp.json        # MCP server configuration
└── .claude/         # Project settings (created by Claude Code)
```

The workspace is mounted read-write so Claude Code can create its `.claude/` project directory and any files it needs. The operator edits `CLAUDE.md` and `.mcp.json` directly on the host — no need to exec into the container.

### How are secrets handled?

For a whitelisted set of environment variables containing sensitive values, the container supports Docker's `_FILE` convention. If `ANTHROPIC_API_KEY_FILE` is set to a file path (e.g. `/run/secrets/anthropic_api_key`), the entrypoint reads the file and exports it as `ANTHROPIC_API_KEY`. This works with Docker secrets, Kubernetes secrets, or any orchestrator that mounts secrets as files. Plain environment variables still work for simpler setups. Only known secret variables are resolved — arbitrary `_FILE` vars are ignored to prevent unintended file reads.

### How does authentication work?

Claude Code supports two auth methods: an **API key** (`ANTHROPIC_API_KEY`) or **OAuth** (for Pro/Max subscribers via `claude login`). The entrypoint detects which is configured and logs the status on startup. If neither is found, it prints instructions for both methods. Yep Anywhere starts regardless — it doesn't handle auth itself, so sessions will fail at the Claude SDK layer until auth is configured. OAuth tokens persist in `~/.claude/` inside the named volume, so the interactive login only needs to happen once per volume lifecycle.

### How are volume permissions handled?

Named volumes and bind mounts can have ownership mismatches with the non-root `claude` user. The entrypoint runs as root and uses `gosu` to fix ownership of `/home/claude` and the workspace before dropping to the `claude` user. This follows the same pattern used by official Docker images (PostgreSQL, Redis, etc.).

### Why no automatic scheduled rebuilds?

A weekly cron rebuild could pull in a broken upstream update with no warning. Builds only trigger on push to `master` or via manual workflow dispatch. The operator decides when to update.

## Repository Structure

```
├── .github/
│   └── workflows/
│       └── build.yml
├── Dockerfile
├── entrypoint.sh
├── docker-compose.yml
├── .env.example
├── workspace/
│   ├── CLAUDE.md
│   └── .mcp.json
├── .gitignore
└── README.md
```

## File: Dockerfile

```dockerfile
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# Install base dependencies + gosu for entrypoint privilege drop
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    gnupg \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS (required by Yep Anywhere, which needs >=20)
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Python 3 (required by uvx to run Python-based MCP servers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager — provides uvx for MCP servers like mcp-ssh-session)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Create non-root user
RUN useradd -m -s /bin/bash claude

# Install Claude Code via official native installer
# https://code.claude.com/docs/en/setup
RUN curl -fsSL https://claude.ai/install.sh | sh

# Install Yep Anywhere (web UI for Claude Code sessions)
# https://github.com/kzahel/yepanywhere
RUN npm install -g yepanywhere

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/claude/workspace

# Yep Anywhere default port
EXPOSE 3400

# Healthcheck — Yep Anywhere serves HTTP on port 3400
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3400/ || exit 1

# Entrypoint runs as root to fix volume permissions, then drops to claude via gosu
ENTRYPOINT ["entrypoint.sh"]
CMD ["yepanywhere"]
```

### Notes on the Dockerfile

- **Base image:** `debian:bookworm-slim` is used instead of `ubuntu:24.04` for a significantly smaller image and reduced attack surface.
- **No `sudo`:** The container has no `sudo` installed. The entrypoint handles privilege management via `gosu`, which is purpose-built for Docker entrypoints and does not persist elevated privileges.
- **`--no-install-recommends`:** All `apt-get install` calls use this flag to avoid pulling unnecessary packages.
- **No `USER` directive:** The Dockerfile does not set `USER claude` because the entrypoint must start as root to fix volume ownership. The entrypoint drops to the `claude` user via `gosu` after setup.
- **Claude Code installer:** Uses the stable vanity URL `https://claude.ai/install.sh` which redirects to the current bootstrap script. The old Google Storage URL with a hardcoded UUID is no longer valid.
- **Node.js 22 LTS:** Node.js 20 reaches end-of-life April 2026. Node.js 22 is the current LTS with support through April 2027.
- **GitHub CLI (`gh`)** authenticates via the `GITHUB_TOKEN` env var — no `gh auth login` needed.
- `uv` is installed via multi-stage COPY from the official image. Python 3 and `python3-venv` are required so `uvx` can create isolated environments for Python-based MCP servers.

## File: entrypoint.sh

```bash
#!/bin/bash
set -e

# --- Whitelisted _FILE variables for Docker secrets convention ---
# Only resolve known secret variables to prevent arbitrary file reads.
SECRETS_WHITELIST=(
    ANTHROPIC_API_KEY
    GITHUB_TOKEN
    CONTEXT7_API_KEY
    BRAVE_API_KEY
    GEMINI_API_KEY
)

for base_var in "${SECRETS_WHITELIST[@]}"; do
    file_var="${base_var}_FILE"
    file_path="${!file_var:-}"
    if [ -n "$file_path" ]; then
        if [ -f "$file_path" ]; then
            export "$base_var"="$(cat "$file_path")"
        else
            echo "WARNING: ${file_var}=${file_path} specified but file does not exist" >&2
        fi
    fi
done

# --- Fix volume permissions ---
# Named volumes and bind mounts may be owned by root on first run.
# Ensure the claude user can write to its home directory and workspace.
chown claude:claude /home/claude
if [ -d /home/claude/.claude ]; then
    chown -R claude:claude /home/claude/.claude
fi
if [ -d /home/claude/workspace ]; then
    chown claude:claude /home/claude/workspace
fi

# --- Check Claude Code authentication status ---
CLAUDE_HOME="/home/claude/.claude"
AUTH_FOUND=false

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "Auth: API key configured via environment variable."
    AUTH_FOUND=true
elif [ -f "${CLAUDE_HOME}/credentials.json" ] || [ -f "${CLAUDE_HOME}/.credentials.json" ]; then
    echo "Auth: OAuth credentials found in ${CLAUDE_HOME}."
    AUTH_FOUND=true
fi

if [ "$AUTH_FOUND" = false ]; then
    echo ""
    echo "============================================"
    echo "  No Claude Code authentication detected."
    echo "============================================"
    echo ""
    echo "  Option 1: Set ANTHROPIC_API_KEY in .env"
    echo ""
    echo "  Option 2: Authenticate interactively (Pro/Max):"
    echo "    docker exec -it \$(hostname) claude login"
    echo ""
    echo "  Yep Anywhere will start, but sessions will"
    echo "  fail until authentication is configured."
    echo "============================================"
    echo ""
fi

# --- Drop to claude user and exec the CMD ---
exec gosu claude "$@"
```

### Notes on entrypoint.sh

- **Whitelisted `_FILE` resolution:** Only a known set of secret variable names are resolved from files. This prevents arbitrary file reads via unexpected `_FILE` env vars. To support a new secret, add it to the `SECRETS_WHITELIST` array.
- **Volume permission fix:** The entrypoint runs as root and chowns `/home/claude`, `~/.claude/`, and the workspace to the `claude` user. This handles both freshly created named volumes (owned by root) and bind mounts with mismatched UIDs. Only top-level directories and the `.claude` config dir are chowned — not a recursive chown of the entire home, which would be slow on large volumes.
- **Auth detection** checks the `ANTHROPIC_API_KEY` env var (including just-resolved `_FILE` values), then OAuth credential files in `~/.claude/`.
- **Yep Anywhere starts regardless** of auth status. Sessions will fail at the Claude SDK layer if not configured, but the web UI is always accessible.
- The credential file check is a best-effort heuristic. If Claude changes its OAuth storage layout, this check may need updating — but it only affects the log message, not functionality.
- **`exec gosu claude "$@"`** drops privileges to the `claude` user and replaces the shell with the CMD process, so signals forward correctly and the container stops cleanly.

## File: docker-compose.yml

```yaml
services:
  claude:
    build: .
    ports:
      - "${PORT:-3400}:3400"
    volumes:
      # Persist Claude Code auth, session history, and Yep Anywhere data
      - claude-home:/home/claude
      # Workspace — CLAUDE.md, .mcp.json, and any files Claude needs
      - ./workspace:/home/claude/workspace
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      # MCP server API keys (referenced via ${VAR} in workspace/.mcp.json)
      - CONTEXT7_API_KEY=${CONTEXT7_API_KEY:-}
      - BRAVE_API_KEY=${BRAVE_API_KEY:-}
      - GEMINI_API_KEY=${GEMINI_API_KEY:-}
      - GITHUB_TOKEN=${GITHUB_TOKEN:-}
    restart: unless-stopped

volumes:
  claude-home:
```

### Notes on docker-compose.yml

- Builds locally from the Dockerfile. No container registry required.
- Port is configurable via `PORT` env var, defaulting to 3400. Place behind a reverse proxy as needed — that's a deployment detail, not part of this stack.
- The `claude-home` named volume persists auth state, session history, and Yep Anywhere metadata across restarts and rebuilds.
- The `./workspace` bind mount is where all operator-managed config lives: `CLAUDE.md`, `.mcp.json`, and any files Claude Code should have access to. Editable directly on the host.
- Env vars default to empty (`:-`) so the container starts even if not all keys are set. Only set the ones your `.mcp.json` needs. Add or remove as your config changes.
- For file-based secrets, use `_FILE` variants (e.g. `ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key`). The entrypoint resolves whitelisted variables automatically.

## File: .github/workflows/build.yml

> **Note:** This workflow publishes the image to GHCR so others can pull it. Not needed for local use. Will be wired up once the image is working.

```yaml
name: Build and Push

on:
  push:
    branches: [master]
  workflow_dispatch:

env:
  IMAGE: ghcr.io/${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE }}:latest
            ${{ env.IMAGE }}:${{ github.sha }}
```

### Notes on the workflow

- `GITHUB_TOKEN` is automatically available — no secrets to configure.
- Two tags per build: `latest` and the commit SHA for rollback.
- Triggers on push to `master` and via manual dispatch.
- No scheduled builds — updates are intentional.

## File: .env.example

```bash
# Port to expose Yep Anywhere on (default: 3400)
PORT=3400

# Your Anthropic API key
# Alternatively, exec into the container and run `claude login` to authenticate
# interactively with a Claude Pro/Max subscription via OAuth
ANTHROPIC_API_KEY=

# For file-based secrets (Docker secrets, Kubernetes, etc.), use _FILE variants:
# ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
# GITHUB_TOKEN_FILE=/run/secrets/github_token

# GitHub personal access token — used by both gh CLI and the GitHub MCP server.
# Create at https://github.com/settings/tokens — scope to your needs.
GITHUB_TOKEN=

# MCP server API keys (only set the ones needed by your workspace/.mcp.json)
CONTEXT7_API_KEY=
BRAVE_API_KEY=
GEMINI_API_KEY=
```

## File: workspace/CLAUDE.md

```markdown
# Homelab Claude

You are running inside a Docker container as a homelab assistant.
You manage infrastructure via MCP servers (SSH, GitHub, etc.) — not by running commands locally.

## Available MCP servers

Check .mcp.json in this directory for configured MCP servers and their capabilities.
```

### Notes on workspace/CLAUDE.md

- This is a starter file. The operator should customize it with specific instructions about their homelab: what hosts exist, what services run where, any conventions or preferences.
- Claude Code reads this file automatically when starting a session in the workspace directory.

## File: workspace/.mcp.json

```json
{
  "mcpServers": {
    "Context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp", "--api-key", "${CONTEXT7_API_KEY}"],
      "description": "Documentation lookup"
    },
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@brave/brave-search-mcp-server", "--transport", "stdio"],
      "env": {
        "BRAVE_API_KEY": "${BRAVE_API_KEY}"
      }
    },
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}"
      },
      "description": "GitHub issues, PRs, and repository access"
    },
    "ssh-session": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-ssh-session"],
      "description": "Persistent SSH session management with async commands and SFTP"
    }
  }
}
```

### Notes on workspace/.mcp.json

- This is project-level MCP config. Claude Code reads it from the working directory automatically.
- Add, remove, or modify servers to suit your homelab. The image ships with `npx` and `uvx` so most MCP servers work out of the box.
- API keys use `${VAR}` syntax — Claude Code interpolates these from the container's environment at runtime. Matching env vars must be set in `.env` and passed through in the compose file.

## File: .gitignore

```
.env
workspace/
```

### Notes on .gitignore

- `.env` contains secrets — never committed.
- `workspace/` is operator-specific configuration. The starter files (`CLAUDE.md`, `.mcp.json`) are tracked in the repo under `workspace/` so they ship with a clone, but `.gitignore` is set up so the operator's customizations don't accidentally get committed back if they're developing on the repo itself. For end users cloning the repo to deploy, this doesn't matter — the starter files are already in the tree.

## File: README.md

Create a README with:
- Brief description: Claude Code + Yep Anywhere in Docker for homelab remote access
- Prerequisites: Docker
- Quick start steps (see Deployment Steps below)
- Workspace section: how to customize `CLAUDE.md` and `.mcp.json`, what runtimes are available (`npx`, `uvx`)
- Authentication section: API key vs OAuth, how each works
- Secrets section: `_FILE` convention for file-based secret injection, list of supported variables
- Link to Yep Anywhere repo: https://github.com/kzahel/yepanywhere
- Link to Claude Code docs: https://code.claude.com/docs/en/setup

## Deployment Steps (for README)

1. Clone the repo
2. Copy `.env.example` to `.env` and fill in API keys (or use `_FILE` variants for file-based secrets)
3. Edit `workspace/CLAUDE.md` with instructions for your homelab
4. Edit `workspace/.mcp.json` to configure MCP servers for your setup
5. Run `docker compose up -d --build`
6. Access Yep Anywhere at `http://<your-server>:3400`
7. If using Claude Pro/Max instead of an API key: `docker exec -it claude-yep-claude-1 claude login`

## Important Caveats

- **Yep Anywhere** is at v0.3.2 as of writing. Check their GitHub repo for updates and breaking changes.
- **Claude Code installer:** The `claude.ai/install.sh` URL is a stable redirect to the current bootstrap script. If builds fail on this step, check https://code.claude.com/docs/en/setup for the current installer command.
- **Adding new secrets:** To support `_FILE` resolution for a new secret variable, add it to the `SECRETS_WHITELIST` array in `entrypoint.sh`.
