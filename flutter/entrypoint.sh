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

# Set up Claude config to skip onboarding
if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  mkdir -p ~/.claude
  cat > ~/.claude.json <<'EOF'
{
  "hasCompletedOnboarding": true
}
EOF
fi

echo "Starting Claude Code..."
exec claude --dangerously-skip-permissions "$@"
