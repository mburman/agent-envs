# Orchestrator (Manager Agent)

The orchestrator runs a "Manager" Claude agent that can spawn and coordinate "Worker" agents to accomplish complex tasks.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST MACHINE                            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     Docker Daemon                          │ │
│  │                                                            │ │
│  │  ┌─────────────────┐                                       │ │
│  │  │    MANAGER      │ spawns    ┌──────────────┐           │ │
│  │  │   (interactive) │──────────▶│   WORKER-1   │           │ │
│  │  │                 │           │  (headless)  │           │ │
│  │  │  - Docker CLI   │ spawns    └──────────────┘           │ │
│  │  │  - Orchestrator │──────────▶┌──────────────┐           │ │
│  │  └─────────────────┘           │   WORKER-2   │           │ │
│  │          │                     │  (headless)  │           │ │
│  │          │ mounts              └──────────────┘           │ │
│  │          ▼                            │                   │ │
│  │  /var/run/docker.sock                 │                   │ │
│  │                                       ▼                   │ │
│  │  ┌─────────────────────────────────────────────────────┐  │ │
│  │  │              SHARED VOLUME (/orchestration)         │  │ │
│  │  │  tasks/        - Task definitions (JSON)            │  │ │
│  │  │  results/      - Completed work                     │  │ │
│  │  │  status/       - Worker status                      │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Build the images

```bash
# Build manager image
cd orchestrator
docker build -t claude-orchestrator .

# Build worker image (flutter environment)
cd ../flutter
docker build -t claude-flutter .
```

### 2. Start the Manager

```bash
cd orchestrator
./run.sh --repo git@github.com:your-user/your-flutter-app.git
```

Options:
- `--repo URL` - Git repo to clone (optional for manager, required for workers)
- `--branch BRANCH` - Branch to clone (default: main)
- `--token FILE` - Claude token file (default: ~/.claude-token)
- `--ssh-key FILE` - SSH key for Git (default: ~/.ssh/id_ed25519)
- `--model MODEL` - Model to use (default: claude-opus-4-5-20251101)

### 3. Talk to the Manager

The Manager is a "Smart Manager" - it knows how to decompose tasks and spawn workers automatically:

```
You: Add dark mode support to the app

Manager: I'll break this into independent tasks and spawn workers for each:
  1. Create theme configuration
  2. Update UI components to use theme
  3. Add theme toggle in settings

Creating tasks and spawning workers...
[Creates task files, spawns 3 workers]

Workers are running. I'll monitor their progress...
[Periodically checks status]

All workers completed. Here's a summary:
- ThemeConfig class created in lib/theme.dart
- 12 widgets updated to use theme colors
- Toggle switch added to settings page
```

## How It Works

### Communication via Shared Volume

The manager and workers communicate through files in `/orchestration/`:

- `tasks/` - Task definitions (JSON with prompt)
- `results/` - Completed work (JSON with output)
- `status/` - Worker status

### Task Format

```json
{
  "id": "task-001",
  "prompt": "Add input validation to login form..."
}
```

### Result Format

```json
{
  "task_id": "task-001",
  "status": "success",
  "output": "Claude's full output...",
  "completed_at": "2026-01-24T10:30:00Z"
}
```

## Manual Worker Control

While the Manager handles this automatically, you can also control workers manually:

```bash
# Create a task file
cat > /orchestration/tasks/task-001.json << 'EOF'
{
  "id": "task-001",
  "prompt": "List all Dart files in the lib/ directory"
}
EOF

# Spawn a worker
/opt/orchestrator/lib/spawn-worker.sh flutter task-001

# Monitor worker
docker logs -f worker-task-001

# Check result
cat /orchestration/results/task-001.json
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Manager container image |
| `entrypoint.sh` | Initialize and start Claude |
| `run.sh` | Host-side convenience script |
| `system-prompt.md` | Smart Manager instructions |
| `lib/spawn-worker.sh` | Spawn worker containers |

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `REPO_URL` | Git repo to clone |
| `REPO_BRANCH` | Branch to clone |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude authentication |
| `ANTHROPIC_MODEL` | Model to use |
| `GIT_USER_NAME` | Git commit author |
| `GIT_USER_EMAIL` | Git commit email |

## Debugging

```bash
# See running workers
docker ps --filter "name=worker-"

# View worker logs
docker logs worker-task-001

# Check orchestration volume contents
docker run --rm -v orchestration-volume:/data alpine ls -la /data/

# Clean up stuck workers
docker rm -f $(docker ps -aq --filter "name=worker-")

# Reset orchestration volume
docker volume rm orchestration-volume
```
