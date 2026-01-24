#!/bin/bash
set -e

cd "$(dirname "$0")"

# Default values
REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-}"
TOKEN_FILE="${HOME}/.claude-token"
SSH_KEY="${HOME}/.ssh/id_ed25519"
WEB_PORT="${WEB_PORT:-8080}"

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
    --port)
      WEB_PORT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --repo <git-url> [options]"
      echo ""
      echo "Options:"
      echo "  --repo URL        Git repo for workers to clone (required)"
      echo "  --branch BRANCH   Branch to clone (default: main)"
      echo "  --token FILE      Claude token file (default: ~/.claude-token)"
      echo "  --ssh-key FILE    SSH key for git (default: ~/.ssh/id_ed25519)"
      echo "  --model MODEL     Model to use (default: claude-opus-4-5-20251101)"
      echo "  --port PORT       Port for Flutter web server (default: 8080)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage"
      exit 1
      ;;
  esac
done

# Validate
if [ -z "$REPO_URL" ]; then
  echo "Error: --repo is required"
  echo "Usage: $0 --repo git@github.com:user/repo.git"
  exit 1
fi

# Get Docker socket GID for permissions
DOCKER_GID=$(stat -f '%g' /var/run/docker.sock 2>/dev/null || stat -c '%g' /var/run/docker.sock 2>/dev/null)
if [ -z "$DOCKER_GID" ]; then
  echo "Warning: Could not determine Docker socket GID"
  DOCKER_GID=0
fi

if [ ! -f "$TOKEN_FILE" ]; then
  echo "Error: Token file not found: $TOKEN_FILE"
  echo "Run 'claude setup-token' and save the token to $TOKEN_FILE"
  exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "Warning: SSH key not found: $SSH_KEY"
fi

# Get git config from host
GIT_USER_NAME="${GIT_USER_NAME:-$(git config --global user.name 2>/dev/null || echo "")}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git config --global user.email 2>/dev/null || echo "")}"

# Create orchestration volume
docker volume create orchestration-volume >/dev/null 2>&1 || true

# Build docker args
DOCKER_ARGS=(
  -it --rm
  --name claude-manager
  --group-add "$DOCKER_GID"
  -p "${WEB_PORT}:${WEB_PORT}"
  -e REPO_URL="$REPO_URL"
  -e REPO_BRANCH="$REPO_BRANCH"
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$TOKEN_FILE" | tr -d '\n')"
  -e GIT_USER_NAME="$GIT_USER_NAME"
  -e GIT_USER_EMAIL="$GIT_USER_EMAIL"
  -e HOST_SSH_KEY="$SSH_KEY"
  -e WEB_PORT="$WEB_PORT"
  -v /var/run/docker.sock:/var/run/docker.sock
  -v orchestration-volume:/orchestration
)

[ -f "$SSH_KEY" ] && DOCKER_ARGS+=(-v "$SSH_KEY:/home/dev/.ssh/id_ed25519:ro")
[ -n "$ANTHROPIC_MODEL" ] && DOCKER_ARGS+=(-e ANTHROPIC_MODEL="$ANTHROPIC_MODEL")

echo "Starting Manager for: $REPO_URL"
docker run "${DOCKER_ARGS[@]}" claude-orchestrator
