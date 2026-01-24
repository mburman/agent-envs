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

# Check required values
if [ -z "$REPO_URL" ]; then
  echo "Error: REPO_URL is required"
  echo "Usage: $0 --repo git@github.com:user/repo.git [options]"
  echo ""
  echo "Options:"
  echo "  --repo URL        Repository URL (required)"
  echo "  --branch BRANCH   Branch to clone (default: main)"
  echo "  --model MODEL     Model to use (default: claude-opus-4-5-20251101)"
  echo "  --token FILE      Token file path (default: ~/.claude-token)"
  echo "  --ssh-key FILE    SSH key path (default: ~/.ssh/id_ed25519)"
  echo ""
  echo "Or set REPO_URL environment variable"
  exit 1
fi

if [ ! -f "$TOKEN_FILE" ]; then
  echo "Error: Token file not found: $TOKEN_FILE"
  echo "Run 'claude setup-token' and save the token to $TOKEN_FILE"
  exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "Error: SSH key not found: $SSH_KEY"
  exit 1
fi

# Build docker args
DOCKER_ARGS=(
  -it --rm
  -e REPO_URL="$REPO_URL"
  -e REPO_BRANCH="$REPO_BRANCH"
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$TOKEN_FILE" | tr -d '\n')"
  -v "$SSH_KEY:/home/dev/.ssh/id_ed25519:ro"
)

if [ -n "$ANTHROPIC_MODEL" ]; then
  DOCKER_ARGS+=(-e ANTHROPIC_MODEL="$ANTHROPIC_MODEL")
fi

# Run container
docker run "${DOCKER_ARGS[@]}" claude-flutter
