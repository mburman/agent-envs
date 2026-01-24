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
SESSION_NAME=""
LIST_SESSIONS=false

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
    --session)
      SESSION_NAME="$2"
      shift 2
      ;;
    --list-sessions)
      LIST_SESSIONS=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 --repo <git-url> [options]"
      echo "       $0 --session <name>  (resume existing session)"
      echo ""
      echo "Options:"
      echo "  --repo URL        Git repo to clone (required for new sessions)"
      echo "  --branch BRANCH   Branch to clone (default: main)"
      echo "  --token FILE      Claude token file (default: ~/.claude-token)"
      echo "  --ssh-key FILE    SSH key for git (default: ~/.ssh/id_ed25519)"
      echo "  --model MODEL     Model to use (default: claude-opus-4-5-20251101)"
      echo "  --port PORT       Port for Flutter web server (default: 8080)"
      echo "  --session NAME    Named session (creates new or resumes existing)"
      echo "  --list-sessions   List available sessions to resume"
      echo ""
      echo "Examples:"
      echo "  $0 --repo git@github.com:user/app.git                    # Fresh start (no session)"
      echo "  $0 --repo git@github.com:user/app.git --session feature  # New named session"
      echo "  $0 --session feature                                     # Resume session"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage"
      exit 1
      ;;
  esac
done

# Handle list-sessions command (doesn't require --repo)
if [ "$LIST_SESSIONS" = true ]; then
  echo "Available sessions:"
  echo "==================="
  docker run --rm -v claude-sessions:/sessions alpine sh -c 'ls -1 /sessions 2>/dev/null' 2>/dev/null | while read session; do
    echo "  $session"
  done || echo "  (no sessions found)"
  echo ""
  echo "To resume: $0 --repo <url> --session <name>"
  exit 0
fi

# Check if session exists (for resuming without --repo)
SESSION_EXISTS=false
if [ -n "$SESSION_NAME" ]; then
  # Check if session directory exists in the sessions volume
  HAS_SESSION=$(docker run --rm -v claude-sessions:/sessions alpine test -d "/sessions/${SESSION_NAME}" && echo "yes" || echo "no")
  if [ "$HAS_SESSION" = "yes" ]; then
    SESSION_EXISTS=true
  fi
fi

# Validate - repo is required for new sessions, optional for existing ones
if [ -z "$REPO_URL" ] && [ "$SESSION_EXISTS" = false ]; then
  echo "Error: --repo is required for new sessions"
  echo "Usage: $0 --repo git@github.com:user/repo.git --session <name>"
  echo ""
  echo "To resume an existing session: $0 --session <name>"
  echo "To list sessions: $0 --list-sessions"
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

# Create session volume
docker volume create claude-sessions >/dev/null 2>&1 || true

# Create per-session repo volume if using sessions
if [ -n "$SESSION_NAME" ]; then
  REPO_VOLUME="claude-repo-${SESSION_NAME}"
  docker volume create "$REPO_VOLUME" >/dev/null 2>&1 || true
fi

# Build docker args
DOCKER_ARGS=(
  -it
  --init
  --name claude-manager
  --group-add "$DOCKER_GID"
  -e TERM="${TERM:-xterm-256color}"
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
  -v claude-sessions:/home/dev/.claude-sessions
)

# Mount per-session repo volume if using sessions
if [ -n "$SESSION_NAME" ]; then
  DOCKER_ARGS+=(-v "${REPO_VOLUME}:/app")
fi

[ -f "$SSH_KEY" ] && DOCKER_ARGS+=(-v "$SSH_KEY:/home/dev/.ssh/id_ed25519:ro")
[ -n "$ANTHROPIC_MODEL" ] && DOCKER_ARGS+=(-e ANTHROPIC_MODEL="$ANTHROPIC_MODEL")
[ -n "$SESSION_NAME" ] && DOCKER_ARGS+=(-e SESSION_NAME="$SESSION_NAME")

# Remove existing stopped container if present
docker rm claude-manager 2>/dev/null || true

if [ -n "$SESSION_NAME" ] && [ "$SESSION_EXISTS" = true ]; then
  echo "Resuming session: $SESSION_NAME"
elif [ -n "$SESSION_NAME" ]; then
  echo "Starting new session: $SESSION_NAME (repo: $REPO_URL)"
else
  echo "Starting Manager for: $REPO_URL"
fi
docker run "${DOCKER_ARGS[@]}" claude-orchestrator
