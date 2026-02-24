FROM debian:bookworm-slim

LABEL org.opencontainers.image.source=https://github.com/danjam/labrat
LABEL org.opencontainers.image.description="Claude Code + Yep Anywhere for homelab remote access"
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.vendor=danjam

ARG DEBIAN_FRONTEND=noninteractive

# Install base dependencies + gosu for entrypoint privilege drop
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    gnupg \
    gosu \
    tmux \
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
RUN useradd -m -s /bin/bash labrat

# Install Claude Code via official native installer as the labrat user
# The installer puts the binary at ~/.local/bin/claude, but /home/labrat is
# overlaid by a named volume at runtime, so copy it to a system-wide location.
# https://code.claude.com/docs/en/setup
USER labrat
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
RUN cp /home/labrat/.local/bin/claude /usr/local/bin/claude

# Disable auto-updates — version is pinned to the image build.
# Rebuild the image to update Claude Code.
ENV CLAUDE_AUTO_UPDATE=0

# Install Yep Anywhere (web UI for AI coding agent sessions)
# https://github.com/kzahel/yepanywhere
RUN npm install -g yepanywhere && npm cache clean --force

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/labrat/workspace

# Yep Anywhere default port
EXPOSE 3400

# Healthcheck — verify Yep Anywhere and Claude Code are functional
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS --max-time 3 http://localhost:3400/ >/dev/null 2>&1 \
     && claude --version >/dev/null 2>&1 \
     || exit 1

# Entrypoint runs as root to fix volume permissions, then drops to labrat via gosu
ENTRYPOINT ["entrypoint.sh"]
CMD ["yepanywhere", "--host", "0.0.0.0"]
