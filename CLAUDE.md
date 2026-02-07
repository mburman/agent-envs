# Claude Code Context

This repo provides Docker environments for running Claude Code with `--dangerously-skip-permissions` in isolated containers.

## Repository Structure

```
agent-envs/
├── README.md              # Overview and quick start
├── CLAUDE.md              # This file
├── build.sh               # Build Docker image
├── run.sh                 # Start Claude in container
├── test.sh                # Run tests
├── .gitignore
└── flutter/               # Flutter environment
    ├── Dockerfile         # Ubuntu + Flutter + Node.js + Claude Code
    ├── entrypoint.sh      # Clones repo, session management, starts Claude
    ├── README.md
    └── lib/
        ├── list-sessions.sh
        ├── delete-session.sh
        └── flutter-web-server.sh
```

## Usage

```bash
./build.sh                                    # Build image
./run.sh --repo git@github.com:user/app.git   # Start new session
./run.sh --session my-feature                 # Resume session
./run.sh --list-sessions                      # List sessions
./test.sh                                     # Run tests
```

## Authentication

```bash
claude setup-token
echo "your-token-here" > ~/.claude-token
chmod 600 ~/.claude-token
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `REPO_URL` | Git repo to clone |
| `REPO_BRANCH` | Branch to clone (default: `main`) |
| `ANTHROPIC_MODEL` | Model to use (default: `claude-opus-4-6`) |
| `SESSION_NAME` | Session name (auto-generated if not provided) |
