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

# Install Claude Code via official native installer as the claude user
# The installer puts the binary at ~/.local/bin/claude, but /home/claude is
# overlaid by a named volume at runtime, so copy it to a system-wide location.
# https://code.claude.com/docs/en/setup
USER claude
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
RUN cp /home/claude/.local/bin/claude /usr/local/bin/claude

# Disable auto-updates — version is pinned to the image build.
# Rebuild the image to update Claude Code.
ENV CLAUDE_AUTO_UPDATE=0

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
