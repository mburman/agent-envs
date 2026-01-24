#!/bin/bash
# Get tasks that are ready to run (pending with all dependencies completed)
# Usage: get-ready-tasks.sh

PLAN_FILE="/orchestration/plan.json"

if [ ! -f "$PLAN_FILE" ]; then
  echo "Error: Plan file not found" >&2
  exit 1
fi

# Find pending tasks whose dependencies are all completed
jq -r '
  .tasks as $tasks |
  .tasks | to_entries[] |
  select(.value.status == "pending") |
  select(
    (.value.depends_on | length == 0) or
    ([.value.depends_on[] | $tasks[.].status == "completed"] | all)
  ) |
  .key
' "$PLAN_FILE"
