#!/bin/bash
# Docker wrapper that prevents direct worker spawning
# Forces use of spawn-worker.sh script

# Check if this is a "docker run" command that looks like a worker spawn attempt
if [ "$1" = "run" ]; then
  # Check for worker-like patterns in the arguments
  ARGS="$*"

  # Detect attempts to spawn workers directly
  if echo "$ARGS" | grep -qiE "(worker|flutter|claude-flutter|task-)" && \
     ! echo "$ARGS" | grep -qE "(spawn-worker|--help)"; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "ERROR: Do not use 'docker run' directly to spawn workers!"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "Use the spawn-worker.sh script instead:"
    echo ""
    echo "  1. Create task file:"
    echo "     cat > /orchestration/tasks/task-001.json << 'EOF'"
    echo "     {\"id\": \"task-001\", \"prompt\": \"Your task prompt here\"}"
    echo "     EOF"
    echo ""
    echo "  2. Spawn worker:"
    echo "     /opt/orchestrator/lib/spawn-worker.sh flutter task-001"
    echo ""
    echo "The script handles image names, environment variables, and volumes."
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    exit 1
  fi
fi

# Pass through to real docker
exec /usr/bin/docker "$@"
