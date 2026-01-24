#!/bin/bash
set -e

# Set up git user config if provided
if [ -n "$GIT_USER_NAME" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# Initialize orchestration directories (on shared volume)
mkdir -p /orchestration/tasks /orchestration/results /orchestration/status

# Check if we're resuming a session with existing repo
SKIP_CLONE=false
if [ -n "$SESSION_NAME" ] && [ -d "/app/.git" ]; then
  echo "Resuming with existing repo..."
  SKIP_CLONE=true
  cd /app
  # Optionally fetch latest if REPO_URL is provided
  if [ -n "$REPO_URL" ]; then
    echo "Fetching latest from origin..."
    git fetch origin "${REPO_BRANCH:-main}" 2>/dev/null || true
  fi
fi

# Clone repo if REPO_URL is provided and we're not resuming
if [ "$SKIP_CLONE" = false ] && [ -n "$REPO_URL" ]; then
  echo "Cloning $REPO_URL (branch: ${REPO_BRANCH:-main})..."
  git clone --branch "${REPO_BRANCH:-main}" --single-branch "$REPO_URL" /app
  cd /app

  # Install Flutter dependencies
  echo "Installing Flutter dependencies..."
  flutter pub get

  # Install dependencies for any subdirectory with a pubspec.yaml (monorepo support)
  find . -mindepth 2 -name "pubspec.yaml" -type f | while read pubspec; do
    dir=$(dirname "$pubspec")
    echo "Installing dependencies for $dir..."
    (cd "$dir" && dart pub get)
  done
elif [ "$SKIP_CLONE" = false ] && [ -z "$REPO_URL" ]; then
  echo "No REPO_URL provided and no existing session repo found."
  echo "Please provide --repo URL or use an existing session."
fi

# Set up Claude config to skip onboarding and enable bypass permissions mode
mkdir -p ~/.claude
cat > ~/.claude.json <<'EOF'
{
  "hasCompletedOnboarding": true
}
EOF

cat > ~/.claude/settings.json <<'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
EOF

# Set default model to Opus (can be overridden via ANTHROPIC_MODEL env var)
export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-opus-4-5-20251101}"

# Session management
SESSIONS_DIR="/home/dev/.claude-sessions"
mkdir -p "$SESSIONS_DIR"
RESUME_FLAG=""

if [ -n "$SESSION_NAME" ]; then
  SESSION_PATH="$SESSIONS_DIR/$SESSION_NAME"

  if [ -d "$SESSION_PATH" ]; then
    echo "Resuming session: $SESSION_NAME"
    # Restore Claude state from saved session
    if [ -d "$SESSION_PATH/.claude" ]; then
      cp -r "$SESSION_PATH/.claude/"* ~/.claude/ 2>/dev/null || true
    fi

    # Find the session ID to resume (must be a valid UUID format)
    RESUME_ID=$(cat "$SESSION_PATH/session-id" 2>/dev/null || echo "")
    # Validate session ID looks like a UUID (8-4-4-4-12 hex pattern)
    if [[ "$RESUME_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
      # Also verify the session file actually exists
      if find ~/.claude/projects -name "${RESUME_ID}.jsonl" -type f 2>/dev/null | grep -q .; then
        RESUME_FLAG="--resume $RESUME_ID"
        echo "Will resume conversation: $RESUME_ID"
      else
        echo "Warning: Session ID found but conversation file missing, starting fresh."
        rm -f "$SESSION_PATH/session-id"
      fi
    elif [ -n "$RESUME_ID" ]; then
      echo "Warning: Invalid session ID '$RESUME_ID', starting fresh."
      rm -f "$SESSION_PATH/session-id"
    fi
  else
    echo "Creating new session: $SESSION_NAME"
    mkdir -p "$SESSION_PATH"
  fi
fi

# Function to save session on exit
save_session() {
  if [ -n "$SESSION_NAME" ]; then
    echo ""
    echo "Saving session: $SESSION_NAME..."
    SESSION_PATH="$SESSIONS_DIR/$SESSION_NAME"
    mkdir -p "$SESSION_PATH"
    cp -r ~/.claude "$SESSION_PATH/" 2>/dev/null || true
    # Save the most recent session ID for resume
    # Claude stores sessions as .jsonl files in ~/.claude/projects/<path>/<session-id>.jsonl
    SESSION_FILES=$(find ~/.claude/projects -name "*.jsonl" -type f 2>/dev/null || true)
    if [ -n "$SESSION_FILES" ]; then
      LATEST_SESSION=$(echo "$SESSION_FILES" | xargs ls -t 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.jsonl$//')
      if [ -n "$LATEST_SESSION" ]; then
        echo "$LATEST_SESSION" > "$SESSION_PATH/session-id"
        echo "Session ID: $LATEST_SESSION"
      fi
    else
      echo "No session conversation files found to save."
      # Remove stale session-id if it exists
      rm -f "$SESSION_PATH/session-id"
    fi
    echo "Session saved."
  fi
}

# Trap EXIT to save session (but only if not using exec)
trap save_session EXIT

echo "Starting Manager with model: $ANTHROPIC_MODEL..."
echo "Orchestration volume: /orchestration"
if [ -n "$SESSION_NAME" ]; then
  echo "Session: $SESSION_NAME"
fi
echo ""

# Start Claude with the Manager system prompt
# The settings.json already sets defaultMode: "bypassPermissions" so we don't need the flag
# Note: We don't use exec so the trap can run on exit
claude --append-system-prompt "$(cat /opt/orchestrator/system-prompt.md)" $RESUME_FLAG "$@"
