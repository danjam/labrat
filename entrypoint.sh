#!/bin/bash
set -e

# --- Whitelisted _FILE variables for Docker secrets convention ---
# Only resolve known secret variables to prevent arbitrary file reads.
SECRETS_WHITELIST=(
    ANTHROPIC_API_KEY
    CLAUDE_CODE_OAUTH_TOKEN
    GITHUB_TOKEN
    CONTEXT7_API_KEY
    BRAVE_API_KEY
    GEMINI_API_KEY
    YEP_PASSWORD
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
WORKSPACE="/home/labrat/workspace"
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
# Ensure the labrat user can write to its home directory and workspace.
chown labrat:labrat /home/labrat
if [ -d /home/labrat/.claude ]; then
    chown -R labrat:labrat /home/labrat/.claude
fi
if [ -d /home/labrat/workspace ]; then
    chown labrat:labrat /home/labrat/workspace
fi

# --- Ensure Claude Code projects directory exists ---
# Yep Anywhere watches ~/.claude/projects/ to discover sessions.
# On a fresh volume this directory doesn't exist, so the FileWatcher
# skips it and the UI shows no projects.
mkdir -p /home/labrat/.claude/projects
chown -R labrat:labrat /home/labrat/.claude

# --- Bootstrap Claude Code onboarding ---
# Pre-seed the onboarding flag so Claude Code skips the interactive
# theme/terms setup on first run. Only create if not already present.
CLAUDE_JSON="/home/labrat/.claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
    echo '{"hasCompletedOnboarding":true}' > "$CLAUDE_JSON"
    chown labrat:labrat "$CLAUDE_JSON"
fi

# --- Seed workspace project ---
# Yep Anywhere's scanner falls back to homedir() when no projects exist,
# starting sessions in /home/labrat instead of /home/labrat/workspace.
# Pre-seeding a project entry ensures the scanner finds workspace first.
# Uses seed.jsonl (no dot prefix — some globs skip dotfiles).
SEED_DIR="/home/labrat/.claude/projects/-home-labrat-workspace"
SEED_FILE="$SEED_DIR/seed.jsonl"
if [ ! -f "$SEED_FILE" ]; then
    mkdir -p "$SEED_DIR"
    echo '{"cwd":"/home/labrat/workspace"}' > "$SEED_FILE"
    chown -R labrat:labrat "$SEED_DIR"
fi

# --- Set up Yep Anywhere authentication ---
YEP_AUTH_FILE="/home/labrat/.yep-anywhere/auth.json"
if [ -z "${YEP_PASSWORD:-}" ]; then
    echo "ERROR: YEP_PASSWORD is required. Set it in .env to protect the web UI." >&2
    exit 1
fi
if [ ! -f "$YEP_AUTH_FILE" ]; then
    gosu labrat yepanywhere --setup-auth "$YEP_PASSWORD"
    echo "Yep Anywhere: authentication configured."
fi

# --- Check agent authentication status ---
echo ""
echo "============================================"
echo "  Agent Authentication Status"
echo "============================================"
echo ""

# Claude Code
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    echo "  Claude Code:  OAuth token configured (Pro/Max)"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "  Claude Code:  API key configured"
else
    echo "  Claude Code:  No credentials"
    echo "                Set CLAUDE_CODE_OAUTH_TOKEN (Pro/Max),"
    echo "                or ANTHROPIC_API_KEY (API) in .env,"
    echo "                or use /login in Yep"
fi
echo ""

# Gemini CLI
if [ -n "${GEMINI_API_KEY:-}" ]; then
    echo "  Gemini CLI:   API key configured"
else
    echo "  Gemini CLI:   No API key"
    echo "                Set GEMINI_API_KEY in .env"
fi

echo ""
echo "============================================"
echo ""

# --- Drop to labrat user and exec the CMD ---
exec gosu labrat "$@"
