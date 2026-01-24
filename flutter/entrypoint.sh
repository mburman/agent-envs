#!/bin/bash
set -e

if [ -z "$REPO_URL" ]; then
  echo "Error: REPO_URL environment variable is required"
  echo "Usage: docker run -e REPO_URL=git@github.com:user/repo.git ..."
  exit 1
fi

echo "Cloning $REPO_URL (branch: $REPO_BRANCH)..."
git clone --branch "$REPO_BRANCH" --single-branch "$REPO_URL" /app

cd /app

echo "Installing dependencies..."
flutter pub get

# Install dependencies for any subdirectory with a pubspec.yaml (monorepo support)
find . -mindepth 2 -name "pubspec.yaml" -type f | while read pubspec; do
  dir=$(dirname "$pubspec")
  echo "Installing dependencies for $dir..."
  (cd "$dir" && dart pub get)
done

# Set up Claude config to skip onboarding and enable bypass permissions mode
mkdir -p ~/.claude
cat > ~/.claude.json <<'EOF'
{
  "hasCompletedOnboarding": true
}
EOF

# Set bypass permissions in settings to avoid the warning dialog
cat > ~/.claude/settings.json <<'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
EOF

# Set default model to Opus (can be overridden via ANTHROPIC_MODEL env var)
export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-opus-4-5-20250514}"

echo "Starting Claude Code with model: $ANTHROPIC_MODEL..."
# Use expect to auto-accept the bypass permissions warning, then hand over to interactive mode
exec /start-claude.exp "$@"
