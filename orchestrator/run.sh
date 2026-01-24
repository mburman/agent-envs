#!/bin/bash
set -e

# Default values
REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-}"
TOKEN_FILE="${HOME}/.claude-token"
SSH_KEY="${HOME}/.ssh/id_ed25519"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)
      REPO_URL="$2"
      shift 2
      ;;
    --branch)
      REPO_BRANCH="$2"
      shift 2
      ;;
    --token)
      TOKEN_FILE="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="$2"
      shift 2
      ;;
    --model)
      ANTHROPIC_MODEL="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--repo URL] [--branch BRANCH] [--token FILE] [--ssh-key FILE] [--model MODEL]"
      exit 1
      ;;
  esac
done

# Validate token file
if [ ! -f "$TOKEN_FILE" ]; then
  echo "Error: Token file not found: $TOKEN_FILE"
  echo "Run 'claude setup-token' and save the token to $TOKEN_FILE"
  exit 1
fi

# Validate SSH key (warn but don't fail - repo might not need it)
if [ ! -f "$SSH_KEY" ]; then
  echo "Warning: SSH key not found: $SSH_KEY"
  echo "Workers won't be able to clone private repos."
fi

# Get git config from host
GIT_USER_NAME="${GIT_USER_NAME:-$(git config --global user.name 2>/dev/null || echo "")}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git config --global user.email 2>/dev/null || echo "")}"

# Create orchestration volume if it doesn't exist
docker volume create orchestration-volume >/dev/null 2>&1 || true

# Build docker args
DOCKER_ARGS=(
  -it --rm
  --name claude-manager
  -e REPO_URL="$REPO_URL"
  -e REPO_BRANCH="$REPO_BRANCH"
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$TOKEN_FILE" | tr -d '\n')"
  -e GIT_USER_NAME="$GIT_USER_NAME"
  -e GIT_USER_EMAIL="$GIT_USER_EMAIL"
  -v /var/run/docker.sock:/var/run/docker.sock
  -v orchestration-volume:/orchestration
)

# Add SSH key mount if it exists
if [ -f "$SSH_KEY" ]; then
  DOCKER_ARGS+=(-v "$SSH_KEY:/home/dev/.ssh/id_ed25519:ro")
fi

# Add model if specified
if [ -n "$ANTHROPIC_MODEL" ]; then
  DOCKER_ARGS+=(-e ANTHROPIC_MODEL="$ANTHROPIC_MODEL")
fi

echo "Starting Manager..."
echo "  Repo: ${REPO_URL:-<none>}"
echo "  Branch: $REPO_BRANCH"
echo "  Orchestration volume: orchestration-volume"
echo ""

# Run container
docker run "${DOCKER_ARGS[@]}" claude-orchestrator
