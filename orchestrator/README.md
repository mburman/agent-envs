# Orchestrator (Manager Agent)

The orchestrator runs a "Manager" Claude agent that coordinates "Worker" sub-agents to accomplish complex tasks.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      DOCKER CONTAINER                           │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      MANAGER                               │ │
│  │              (interactive Claude session)                  │ │
│  │                                                            │ │
│  │  /app/                    .worktrees/                      │ │
│  │  (main repo)              ├── task-001/  ◄── Worker 1      │ │
│  │       │                   ├── task-002/  ◄── Worker 2      │ │
│  │       │                   └── task-003/  ◄── Worker 3      │ │
│  │       │                         │                          │ │
│  │       │    patches              │                          │ │
│  │       ◄─────────────────────────┘                          │ │
│  │                                                            │ │
│  │  Workers = Claude sub-agents via Task tool                 │ │
│  │  Isolation = Git worktrees (instant, no container startup) │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  /orchestration/                                                │
│  ├── plan.json      - Task dependency graph                     │
│  ├── tasks/         - Task definitions                          │
│  ├── results/       - Patches and result metadata               │
│  └── status/        - Worker heartbeats                         │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Build the image

```bash
./build.sh
```

### 2. Start the Manager

```bash
./run.sh --repo git@github.com:your-user/your-flutter-app.git
```

Options:
- `--repo URL` - Git repo to clone
- `--branch BRANCH` - Branch to clone (default: main)
- `--session NAME` - Named session for persistence
- `--token FILE` - Claude token file (default: ~/.claude-token)
- `--ssh-key FILE` - SSH key for Git (default: ~/.ssh/id_ed25519)

### 3. Talk to the Manager

```
You: Add dark mode support to the app

Manager: I'll break this into independent tasks and spawn workers:
  1. Create theme configuration
  2. Update UI components to use theme
  3. Add theme toggle in settings

[Creates worktrees, spawns sub-agents via Task tool]
[Workers make changes in parallel]
[Manager collects patches, reviews, commits]
```

## How Workers Work

Workers are **Claude Code sub-agents** spawned via the Task tool:

1. Manager creates a git worktree: `.worktrees/task-001/`
2. Manager spawns a sub-agent with `task-worker` type
3. Sub-agent works in the isolated worktree
4. Git hooks prevent the sub-agent from committing
5. Manager collects a patch from the worktree
6. Manager applies patch to main `/app` directory

### Why Worktrees Instead of Docker?

| Aspect | Docker Containers | Git Worktrees |
|--------|-------------------|---------------|
| Startup | 10-30 seconds | Instant |
| Isolation | OS-level | Filesystem |
| Parallelism | Unlimited | ~7 sub-agents |
| Overhead | High (clone, deps) | None |

## Manual Workflow

While the Manager handles this automatically, you can control it manually:

```bash
# 1. Create task file
cat > /orchestration/tasks/task-001.json << 'EOF'
{"id": "task-001", "prompt": "Add input validation to login form..."}
EOF

# 2. Create worktree
/opt/orchestrator/lib/spawn-worker.sh task-001

# 3. Spawn sub-agent (Manager does this via Task tool)
# The spawn-worker.sh output shows how to call the Task tool

# 4. When worker completes, collect patch
/opt/orchestrator/lib/worktree/collect-patch.sh task-001

# 5. Apply patch
git apply /orchestration/results/task-001.patch

# 6. Cleanup
/opt/orchestrator/lib/worktree/cleanup-worktree.sh task-001
```

## Scripts

| Script | Purpose |
|--------|---------|
| `spawn-worker.sh <task-id>` | Create worktree, output sub-agent instructions |
| `check-workers.sh` | Show worker status |
| `show-plan.sh` | Display task dependency graph |
| `get-ready-tasks.sh` | List tasks ready to run |
| `update-task-status.sh <id> <status>` | Update task status |
| `cleanup.sh --worktrees\|--state\|--all` | Clean up |
| `worktree/collect-patch.sh <id>` | Collect patch from worktree |
| `worktree/cleanup-worktree.sh <id>` | Remove worktree |

## Session Management

Sessions persist conversation history and repo state:

```bash
# Start new session
./run.sh --repo git@... --session my-feature

# Resume session
./run.sh --session my-feature

# List sessions
./run.sh --list-sessions
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `REPO_URL` | Git repo to clone |
| `REPO_BRANCH` | Branch to clone |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude authentication |
| `ANTHROPIC_MODEL` | Model to use |
| `SESSION_NAME` | Named session for persistence |
