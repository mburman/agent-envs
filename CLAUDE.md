# Claude Code Context

This repo contains Docker environments for running Claude Code with `--dangerously-skip-permissions` in isolated containers.

## Repository Structure

```
agent-envs/
├── README.md              # Overview and quick start
├── CLAUDE.md              # This file
├── build.sh               # Build all images
├── run.sh                 # Start the Manager
├── test.sh                # Run tests
├── orchestrator/          # Manager agent environment
│   ├── Dockerfile         # Ubuntu + Flutter + Docker CLI + Claude Code
│   ├── entrypoint.sh      # Clones repo, starts Claude with system prompt
│   ├── system-prompt.md   # Manager orchestration instructions
│   ├── README.md
│   └── lib/               # Orchestration scripts
│       ├── spawn-worker.sh
│       ├── show-plan.sh
│       ├── get-ready-tasks.sh
│       ├── update-task-status.sh
│       ├── list-workers.sh
│       ├── list-sessions.sh
│       ├── delete-session.sh
│       └── cleanup.sh
└── flutter/               # Worker agent environment
    ├── Dockerfile         # Ubuntu + Flutter SDK + Node.js + Claude Code
    ├── entrypoint.sh      # Clones repo, supports worker mode
    └── README.md
```

## Orchestration System

The orchestration system enables a Manager agent to coordinate multiple Worker agents:

**Manager** (`orchestrator/`):
- Interactive Claude Code session you talk to directly
- Has Flutter, Docker CLI, and all dev tools
- Creates dependency graphs of tasks
- Spawns workers for parallel execution
- Applies worker patches and commits (quality control)
- Can run `flutter test` and `flutter run` for verification

**Workers** (`flutter/` in worker mode):
- Headless Claude Code instances (`claude -p`)
- Clone repo fresh, execute one task, exit
- Cannot commit or push (git hooks block it)
- Generate patches for Manager to review/apply

**Communication**:
- Shared Docker volume at `/orchestration`
- `plan.json` - Dependency graph with task status
- `tasks/*.json` - Task definitions with prompts
- `results/*.json` and `*.patch` - Worker output

**Usage**:
```bash
./build.sh                                    # Build images
./run.sh --repo git@github.com:user/app.git   # Start Manager
./test.sh                                     # Run tests
```

## Flutter Environment

The Flutter environment (`flutter/`) includes:
- Ubuntu 22.04, Flutter SDK (stable), Dart SDK, Node.js 20, Claude Code CLI
- Build tools: clang, cmake, ninja, pkg-config, GTK3

**Monorepo support**: The entrypoint automatically detects and installs dependencies for any subdirectory containing a `pubspec.yaml`. This handles common structures like:
- `packages/*/pubspec.yaml` (Dart packages)
- `mcp/pubspec.yaml` (MCP servers)
- Any other nested Dart/Flutter packages

## Adding a New Environment

1. Create a new directory (e.g., `python/`, `node/`, `rust/`)
2. Add these files:
   - `Dockerfile` - Base image with all tools needed
   - `entrypoint.sh` - Script that clones repo, installs deps, starts Claude
   - `README.md` - Environment-specific docs

3. Update the root README.md to list the new environment

## Common Patterns

Each environment follows this pattern:

```dockerfile
# Dockerfile
FROM base-image
# Install language toolchain
# Install Node.js (for Claude Code)
# Install Claude Code: npm install -g @anthropic-ai/claude-code
# Prepare SSH for GitHub
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

```bash
# entrypoint.sh
#!/bin/bash
set -e
# Validate REPO_URL
# Clone repo
# Install dependencies
exec claude --dangerously-skip-permissions "$@"
```

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

### Limitations

Tokens from `claude setup-token` have limited scopes (`user:inference` only). Features requiring `user:profile` scope (like `/usage`) will fail with permission errors. All coding features work normally.

## Environment Variables (All Environments)

| Variable | Purpose |
|----------|---------|
| `REPO_URL` | SSH URL of repo to clone |
| `REPO_BRANCH` | Branch to clone (default: `main`) |
| `ANTHROPIC_MODEL` | Model to use (default: `claude-opus-4-5-20251101`) |
| `SESSION_NAME` | Named session to create or resume |

## Testing

```bash
# Run the full test suite
./test.sh

# Skip build if images already exist
./test.sh --skip-build

# Manual testing
./run.sh --repo git@github.com:user/test-repo.git
```

Tests verify:
- All required tools installed (Flutter, Docker CLI, Claude Code, jq)
- Orchestrator scripts exist and are executable
- Plan parsing logic works correctly
- Task status updates work
- sudo docker access works

## Session Management

Named sessions persist your Claude conversation and repo state across container restarts. This is useful for long-running projects or when you need to stop and resume work.

```bash
# Start a new named session
./run.sh --repo git@github.com:user/app.git --session dark-mode-feature

# List available sessions
./run.sh --list-sessions

# Resume an existing session (no --repo needed!)
./run.sh --session dark-mode-feature

# Inside the container, you can also:
/opt/orchestrator/lib/list-sessions.sh           # List sessions
/opt/orchestrator/lib/delete-session.sh my-session  # Delete a session
```

Each session persists:
- Claude conversation history (for `--resume`)
- Repository state including uncommitted changes (per-session volume)

Docker volumes used:
- `claude-sessions` - Session metadata and Claude state
- `claude-repo-<session-name>` - Per-session repo state
- `orchestration-volume` - Shared orchestration state (plan, tasks, results)
