# Labrat

Claude Code + [Yep Anywhere](https://github.com/kzahel/yepanywhere) in Docker for homelab remote access. Access Claude Code from any device via a web browser.

## Quick Start

```bash
git clone <repo-url> && cd labrat
cp .env.example .env          # Fill in API keys
vim workspace/CLAUDE.md       # Customize instructions for your homelab
vim workspace/.mcp.json       # Configure MCP servers
docker compose up -d --build
```

Open `http://<your-server>:3400` in a browser.

## Authentication

**API key:** Set `ANTHROPIC_API_KEY` in `.env`. Done.

**Claude Pro/Max (OAuth):** Leave `ANTHROPIC_API_KEY` blank, start the container, then:

```bash
docker exec -it labrat-claude-1 claude login
```

This is a one-time interactive flow. OAuth tokens persist in the `claude-home` volume across restarts.

## Workspace

All Claude Code project config lives in `./workspace/`, bind-mounted into the container:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Instructions and context for Claude Code sessions |
| `.mcp.json` | MCP server configuration (read by Claude Code automatically) |
| `.claude/` | Project settings (created by Claude Code at runtime) |

Edit these directly on the host. Changes take effect on the next session.

## MCP Servers

The image ships with `npx` and `uvx`, so most MCP servers work out of the box. Configure them in `workspace/.mcp.json`. API keys use `${VAR}` syntax — Claude Code reads them from the container's environment at runtime.

The starter config includes:

- **Context7** — documentation lookup
- **Brave Search** — web search
- **GitHub** — issues, PRs, repository access
- **SSH Session** — persistent SSH with async commands and SFTP

The `gh` CLI is also installed and authenticates via `GITHUB_TOKEN`.

## Secrets

API keys can be set as plain environment variables in `.env`, or via Docker's `_FILE` convention for file-based secret injection:

```bash
# Plain
ANTHROPIC_API_KEY=sk-ant-...

# File-based (Docker secrets, Kubernetes, etc.)
ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
```

Supported `_FILE` variables: `ANTHROPIC_API_KEY`, `GITHUB_TOKEN`, `CONTEXT7_API_KEY`, `BRAVE_API_KEY`, `GEMINI_API_KEY`. To add more, edit the `SECRETS_WHITELIST` in `entrypoint.sh`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3400` | Host port for Yep Anywhere |
| `ANTHROPIC_API_KEY` | | Claude API key (or use OAuth) |
| `GITHUB_TOKEN` | | GitHub PAT for `gh` CLI and GitHub MCP |
| `CONTEXT7_API_KEY` | | Context7 MCP server |
| `BRAVE_API_KEY` | | Brave Search MCP server |
| `GEMINI_API_KEY` | | Gemini MCP server |

## Links

- [Claude Code docs](https://code.claude.com/docs/en/setup)
- [Yep Anywhere](https://github.com/kzahel/yepanywhere)
