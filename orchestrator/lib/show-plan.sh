#!/bin/bash
set -e
# Display the task dependency graph and current progress
# Usage: show-plan.sh

PLAN_FILE="/orchestration/plan.json"

if [ ! -f "$PLAN_FILE" ]; then
  echo "No plan found. Ask the Manager to create one first."
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
jq -r '.goal' "$PLAN_FILE" | xargs -I{} echo "  GOAL: {}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get counts
TOTAL=$(jq '.tasks | length' "$PLAN_FILE")
COMPLETED=$(jq '[.tasks[] | select(.status == "completed")] | length' "$PLAN_FILE")
RUNNING=$(jq '[.tasks[] | select(.status == "running")] | length' "$PLAN_FILE")
PENDING=$(jq '[.tasks[] | select(.status == "pending")] | length' "$PLAN_FILE")
FAILED=$(jq '[.tasks[] | select(.status == "failed")] | length' "$PLAN_FILE")

echo "  Progress: $COMPLETED/$TOTAL completed | $RUNNING running | $PENDING pending | $FAILED failed"
echo ""
echo "───────────────────────────────────────────────────────────────"
echo ""

# Display each task with status and dependencies
jq -r '.tasks | to_entries[] | "\(.key)|\(.value.name)|\(.value.status)|\(.value.depends_on | join(","))"' "$PLAN_FILE" | \
while IFS='|' read -r id name status deps; do
  # Status icon
  case "$status" in
    completed) icon="✓" ;;
    running)   icon="●" ;;
    pending)   icon="○" ;;
    failed)    icon="✗" ;;
    *)         icon="?" ;;
  esac

  # Format dependencies
  if [ -n "$deps" ]; then
    deps_str=" (after: $deps)"
  else
    deps_str=" (no dependencies)"
  fi

  printf "  %s %-12s  %-30s%s\n" "$icon" "[$id]" "$name" "$deps_str"
done

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  Legend: ✓ completed  ● running  ○ pending  ✗ failed"
echo "═══════════════════════════════════════════════════════════════"
echo ""
