#!/bin/bash
# Spawn a worker container to execute a task
# Usage: spawn-worker.sh <environment> <task-id>

set -e

ENVIRONMENT="${1:-flutter}"
TASK_ID="$2"
STAGGER_SECONDS=5  # Minimum seconds between worker starts

if [ -z "$TASK_ID" ]; then
  echo "Usage: spawn-worker.sh <environment> <task-id>"
  echo "Example: spawn-worker.sh flutter task-001"
  exit 1
fi

# Validate task file exists
TASK_FILE="/orchestration/tasks/${TASK_ID}.json"
if [ ! -f "$TASK_FILE" ]; then
  echo "Error: Task file not found: $TASK_FILE"
  echo "Create it first with: echo '{\"id\":\"$TASK_ID\",\"prompt\":\"...\"}' > $TASK_FILE"
  exit 1
fi

# Container name based on task ID
CONTAINER_NAME="worker-${TASK_ID}"

# Use real docker binary (bypass wrapper)
DOCKER="/usr/bin/docker"

# Check if container already exists
if sudo $DOCKER ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Error: Container $CONTAINER_NAME already exists"
  echo "Check status with: docker ps -a --filter name=$CONTAINER_NAME"
  exit 1
fi

echo "Spawning worker: $CONTAINER_NAME (environment: $ENVIRONMENT, task: $TASK_ID)"

# Update plan status to running (if plan exists)
PLAN_FILE="/orchestration/plan.json"
if [ -f "$PLAN_FILE" ]; then
  /opt/orchestrator/lib/update-task-status.sh "$TASK_ID" running
fi

# Build docker arguments
DOCKER_ARGS=(
  -d
  --rm
  --name "$CONTAINER_NAME"
  -e WORKER_MODE=true
  -e TASK_ID="$TASK_ID"
  -e REPO_URL="$REPO_URL"
  -e REPO_BRANCH="$REPO_BRANCH"
  -e CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
  -e ANTHROPIC_MODEL="$ANTHROPIC_MODEL"
  -e GIT_USER_NAME="$GIT_USER_NAME"
  -e GIT_USER_EMAIL="$GIT_USER_EMAIL"
  -v orchestration-volume:/orchestration
)

# Mount SSH key if host path is provided
# Note: HOST_SSH_KEY is a host path, so we can't check if it exists from inside the container
# Docker will use the host's filesystem for the volume mount
if [ -n "$HOST_SSH_KEY" ]; then
  DOCKER_ARGS+=(-v "$HOST_SSH_KEY:/home/dev/.ssh/id_ed25519:ro")
else
  echo "Warning: HOST_SSH_KEY not set, workers won't be able to clone private repos"
fi

# Image name based on environment
IMAGE_NAME="claude-${ENVIRONMENT}"

# Stagger worker starts to avoid API rate limits and timeouts
LAST_SPAWN_FILE="/orchestration/status/.last-spawn"
NOW=$(date +%s)

if [ -f "$LAST_SPAWN_FILE" ]; then
  LAST_SPAWN=$(cat "$LAST_SPAWN_FILE" 2>/dev/null || echo "0")
  ELAPSED=$((NOW - LAST_SPAWN))

  if [ "$ELAPSED" -lt "$STAGGER_SECONDS" ]; then
    WAIT_TIME=$((STAGGER_SECONDS - ELAPSED))
    echo "Staggering start: waiting ${WAIT_TIME}s before spawning..."
    sleep "$WAIT_TIME"
  fi
fi

# Record this spawn time
echo "$(date +%s)" > "$LAST_SPAWN_FILE"

# Run the worker container
sudo $DOCKER run "${DOCKER_ARGS[@]}" "$IMAGE_NAME"

echo "Worker spawned: $CONTAINER_NAME"
echo "Monitor with: docker logs -f $CONTAINER_NAME"
echo "Check result: cat /orchestration/results/${TASK_ID}.json"
