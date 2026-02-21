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

# --- Copy starter config if not already present ---
WORKSPACE="/home/claude/workspace"
for example_file in "$WORKSPACE"/*.example "$WORKSPACE"/.*.example; do
    [ -f "$example_file" ] || continue
    live_file="${example_file%.example}"
    if [ ! -f "$live_file" ]; then
        cp "$example_file" "$live_file"
        echo "Created $(basename "$live_file") from example template."
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
