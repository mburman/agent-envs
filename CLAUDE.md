# Claude Code Context

This repo contains Docker environments for running Claude Code with `--dangerously-skip-permissions` in isolated containers.

## Repository Structure

```
agent-envs/
├── README.md              # Overview and quick start
├── CLAUDE.md              # This file
├── build.sh               # Build all images
├── run.sh                 # Start the Manager
├── test.sh                # Run tests (includes functional worktree tests)
├── lib/
│   └── worktree/          # Worktree management scripts
│       ├── create-worktree.sh
│       ├── collect-patch.sh
│       ├── cleanup-worktree.sh
│       └── cleanup-all.sh
├── .claude/
│   └── agents/
│       └── task-worker.md # Worker sub-agent definition
└── orchestrator/          # Manager agent environment
    ├── Dockerfile         # Ubuntu + Flutter + Docker CLI + Claude Code
    ├── entrypoint.sh      # Clones repo, starts Claude with system prompt
    ├── system-prompt.md   # Manager orchestration instructions
    ├── README.md
    └── lib/               # Orchestration scripts (worktree/ copied from lib/)
        ├── spawn-worker.sh
        ├── check-workers.sh
        ├── show-plan.sh
        ├── get-ready-tasks.sh
        ├── update-task-status.sh
        └── cleanup.sh
```

## Orchestration System

The orchestration system enables a Manager agent to coordinate multiple Worker sub-agents:

**Manager** (`orchestrator/`):
- Interactive Claude Code session you talk to directly
- Runs in Docker container with `--dangerously-skip-permissions` (sandboxed)
- Has Flutter, all dev tools, and Claude Code
- Creates dependency graphs of tasks
- Spawns worker sub-agents via Claude's Task tool
- Workers run in isolated git worktrees
- Collects patches and commits (quality control)
- Can run `flutter test` and `flutter run` for verification

**Workers** (sub-agents in worktrees):
- Claude Code sub-agents spawned via Task tool
- Work in isolated git worktrees (`.worktrees/<task-id>/`)
- Cannot commit or push (git hooks block it)
- Generate patches for Manager to review/apply
- Much faster than Docker containers (~instant startup)

**Communication**:
- `/orchestration` directory (Docker volume)
- `plan.json` - Dependency graph with task status
- `tasks/*.json` - Task definitions with prompts
- `results/*.json` and `*.patch` - Worker output
- `status/*.json` - Worker heartbeat/progress

**Usage**:
```bash
./build.sh                                    # Build images
./run.sh --repo git@github.com:user/app.git   # Start Manager
./test.sh                                     # Run tests
```

## Worker Architecture (Worktrees + Sub-Agents)

Workers are implemented as:
1. **Git worktrees** for filesystem isolation
2. **Claude Code sub-agents** (via Task tool) for execution

### How It Works

1. Manager creates a worktree: `.worktrees/task-001/` on branch `worker/task-001`
2. Manager spawns a sub-agent via Task tool with `task-worker` type
3. Sub-agent works in the worktree, making code changes
4. Git hooks prevent the sub-agent from committing
5. Manager collects a patch from the worktree changes
6. Manager applies patch to main `/app` directory
7. Manager reviews, tests, and commits

### Benefits Over Docker Workers

| Aspect | Docker Workers | Worktree Sub-Agents |
|--------|----------------|---------------------|
| Startup | 10-30s (clone + deps) | <1s (instant) |
| Isolation | OS-level | Filesystem (worktrees) |
| Parallelism | Unlimited | ~7 sub-agents |
| Dependencies | Fresh install each | Shared with Manager |

## Authentication

Claude Code uses a long-lived OAuth token passed via `CLAUDE_CODE_OAUTH_TOKEN` environment variable.

### Getting a Token

```bash
# Get a token (one-time, requires Claude Pro/Max):
claude setup-token

# Follow browser prompt, then save the token:
echo "your-token-here" > ~/.claude-token
chmod 600 ~/.claude-token
```

### Using the Token

The entrypoint script creates `~/.claude.json` with `hasCompletedOnboarding: true` to skip the login prompt. Pass the token like this:

```bash
-e CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.claude-token | tr -d '\n')"
```

**Important**: Use `tr -d '\n'` to strip newlines, which cause "invalid header value" errors.

## Environment Variables (All Environments)

| Variable | Purpose |
|----------|---------|
| `REPO_URL` | SSH URL of repo to clone |
| `REPO_BRANCH` | Branch to clone (default: `main`) |
| `ANTHROPIC_MODEL` | Model to use (default: `claude-opus-4-5-20251101`) |
| `SESSION_NAME` | Session to create or resume (auto-generated if not provided) |

## Testing

```bash
# Run the full test suite
./test.sh

# Skip build if images already exist
./test.sh --skip-build

# Manual testing
./run.sh --repo git@github.com:user/test-repo.git
```

## Session Management

Sessions persist your Claude conversation and repo state across container restarts. Session IDs are auto-generated if not provided.

```bash
# Start a new session (auto-generates ID like s-20250124-143022)
./run.sh --repo git@github.com:user/app.git

# Start with a custom session name
./run.sh --repo git@github.com:user/app.git --session dark-mode-feature

# List available sessions
./run.sh --list-sessions

# Resume an existing session (no --repo needed!)
./run.sh --session dark-mode-feature

# Inside the container:
/opt/orchestrator/lib/list-sessions.sh           # List sessions
/opt/orchestrator/lib/delete-session.sh my-session  # Delete a session
```

Each session persists:
- Claude conversation history (for `--resume`)
- Repository state including uncommitted changes
- Worktrees and orchestration state

Docker volumes used:
- `claude-sessions` - Session metadata and Claude state
- `claude-repo-<session-name>` - Per-session repo state
- `orchestration-volume` - Shared orchestration state

## Orchestrator Scripts

| Script | Purpose |
|--------|---------|
| `spawn-worker.sh <task-id>` | Create worktree, print sub-agent instructions |
| `check-workers.sh` | Show worker status (running/completed/stuck) |
| `show-plan.sh` | Display dependency graph |
| `get-ready-tasks.sh` | List tasks with no unmet dependencies |
| `update-task-status.sh <id> <status>` | Update task status in plan |
| `cleanup.sh --worktrees\|--state\|--all` | Clean up worktrees and/or state |
| `worktree/collect-patch.sh <task-id>` | Collect patch from completed worktree |
| `worktree/cleanup-worktree.sh <task-id>` | Remove single worktree |
