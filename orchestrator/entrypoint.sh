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
mkdir -p /orchestration/tasks /orchestration/results /orchestration/status /orchestration/help-requests

# Clone repo if REPO_URL is provided
if [ -n "$REPO_URL" ]; then
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
else
  echo "No REPO_URL provided. Manager will start without a repo context."
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

echo "Starting Manager with model: $ANTHROPIC_MODEL..."
echo "Orchestration volume: /orchestration"
echo ""

# Start Claude with the Manager system prompt
exec /start-claude.exp --append-system-prompt "$(cat /opt/orchestrator/system-prompt.md)" "$@"
