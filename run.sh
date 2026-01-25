#!/bin/bash
set -e

cd "$(dirname "$0")"

# Default values
REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-}"
TOKEN_FILE="${HOME}/.claude-token"
SSH_KEY="${HOME}/.ssh/id_ed25519"
WEB_PORT="${WEB_PORT:-}"
SESSION_NAME=""
LIST_SESSIONS=false
CLEAN_ALL=false

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
    --clean-all)
      CLEAN_ALL=true
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
      echo "  --port PORT       Port for Flutter web server (default: random 8080-8999)"
      echo "  --session NAME    Named session (auto-generated if not provided)"
      echo "  --list-sessions   List available sessions to resume"
      echo "  --clean-all       Reset all state (sessions, repos)"
      echo ""
      echo "Examples:"
      echo "  $0 --repo git@github.com:user/app.git                    # New auto-named session"
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

# Auto-generate session ID if not provided
if [ -z "$SESSION_NAME" ] && [ "$LIST_SESSIONS" = false ] && [ "$CLEAN_ALL" = false ]; then
  SESSION_NAME="s-$(date +%Y%m%d-%H%M%S)"
fi

# Auto-generate random port if not provided (range 8080-8999)
if [ -z "$WEB_PORT" ]; then
  WEB_PORT=$((8080 + RANDOM % 920))
fi

# Handle list-sessions command (doesn't require --repo)
if [ "$LIST_SESSIONS" = true ]; then
  echo "Available sessions:"
  echo "==================="
  docker run --rm -v claude-sessions:/sessions alpine sh -c 'ls -1 /sessions 2>/dev/null' 2>/dev/null | while read session; do
    echo "  $session"
  done || echo "  (no sessions found)"
  echo ""
  echo "To resume: $0 --session <name>"
  exit 0
fi

# Handle clean-all command (doesn't require --repo)
if [ "$CLEAN_ALL" = true ]; then
  echo "Resetting all state..."
  echo ""

  # Stop and remove all claude containers
  CONTAINERS=$(docker ps -aq --filter "name=claude-" 2>/dev/null || true)
  if [ -n "$CONTAINERS" ]; then
    echo "Stopping containers..."
    docker rm -f $CONTAINERS 2>/dev/null || true
  fi

  # Remove sessions volume
  echo "Removing sessions volume..."
  docker volume rm claude-sessions 2>/dev/null || true

  # Remove all per-session repo volumes
  echo "Removing repo volumes..."
  docker volume ls -q --filter "name=claude-repo-" 2>/dev/null | while read vol; do
    docker volume rm "$vol" 2>/dev/null || true
  done

  echo ""
  echo "Done. All state has been reset:"
  echo "  ✓ Containers removed"
  echo "  ✓ Sessions volume removed"
  echo "  ✓ Repo volumes removed"
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
  echo "Usage: $0 --repo git@github.com:user/repo.git"
  echo ""
  echo "To resume an existing session: $0 --session <name>"
  echo "To list sessions: $0 --list-sessions"
  exit 1
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

# Create session volume
docker volume create claude-sessions >/dev/null 2>&1 || true

# Create per-session repo volume if using sessions
if [ -n "$SESSION_NAME" ]; then
  REPO_VOLUME="claude-repo-${SESSION_NAME}"
  docker volume create "$REPO_VOLUME" >/dev/null 2>&1 || true
fi

# Container name based on session
CONTAINER_NAME="claude-${SESSION_NAME}"

# Build docker args
DOCKER_ARGS=(
  -it
  --init
  --name "$CONTAINER_NAME"
  -e TERM="${TERM:-xterm-256color}"
  -p "${WEB_PORT}:${WEB_PORT}"
  -e REPO_URL="$REPO_URL"
  -e REPO_BRANCH="$REPO_BRANCH"
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$TOKEN_FILE" | tr -d '\n')"
  -e GIT_USER_NAME="$GIT_USER_NAME"
  -e GIT_USER_EMAIL="$GIT_USER_EMAIL"
  -e WEB_PORT="$WEB_PORT"
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
docker rm "$CONTAINER_NAME" 2>/dev/null || true

if [ "$SESSION_EXISTS" = true ]; then
  echo "Resuming session: $SESSION_NAME (port: $WEB_PORT)"
else
  echo "Starting new session: $SESSION_NAME (repo: $REPO_URL, port: $WEB_PORT)"
fi
docker run "${DOCKER_ARGS[@]}" claude-flutter
