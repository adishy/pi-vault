# AGENTS.md

Context and implementation details for AI agents working in this repository.

## Project Purpose

This project provides a containerized environment for running the PI coding agent against a copy of an Obsidian vault (or any file directory). It is designed for safe, isolated AI-assisted editing with full change tracking via git.

## Requirements

### Core Workflow

1. **Isolation**: The source vault is never modified. It is mounted read-only into the container and copied to a writable location at startup.
2. **Git tracking**: A fresh git repository is created inside the container with all vault files committed as the initial state. This allows diffing changes made by PI.
3. **Session-based**: Each invocation creates a unique session (random 8-char UUID). Multiple sessions can run concurrently without conflict.
4. **Background execution**: The container runs in the background. Users attach interactively via `docker exec` to launch PI's TUI.
5. **Writeback to tmp**: When the user is done, the modified vault (including `.git/`) is copied to a host-accessible tmp directory. The user can then `git status` / `git diff` to review changes before manually merging.
6. **Cleanup**: Sessions can be stopped and containers removed via `--stop`.

### Authentication

- PI uses AWS Bedrock as its model provider.
- A bearer token is passed via the `AWS_BEARER_TOKEN_BEDROCK` environment variable.
- The token is provided as a script argument and injected into the container at runtime (not baked into the image).

### Container Lifecycle

| Action | What happens |
|--------|-------------|
| Start (default) | Build image if missing → generate session ID → create host tmp dir → run container in bg |
| `--exec` | `docker exec -it` into running container, launch `pi` in vault working dir |
| `--writeback` | Copy `/vault/<basename>` (with `.git/`) to `/tmp/session/` (host-mounted volume) |
| `--stop` | `docker stop` + `docker rm` the session container |
| `--rebuild` | Stop all sessions → `docker build` fresh image → start new session |

### File Layout Inside Container

```
/mnt/vault-source/       # Read-only bind mount of host vault
/vault/<basename>/       # Writable copy with git repo (PI works here)
/tmp/session/            # Volume mount → <tmp_dir>/<session_id> on host
```

### File Layout on Host (after writeback)

```
<tmp_dir>/<session_id>/<basename>/
├── .git/                # Full git repo for diffing
├── file1.md
├── file2.md
└── ...
```

## Implementation Details

### Dockerfile (`Dockerfile`)

- Base: `node:22-slim` (lightweight, has npm for PI installation)
- Installs: `git` (for repo management), `@earendil-works/pi-coding-agent` (globally via npm)
- Entrypoint: `/entrypoint.sh`

### Entrypoint (`entrypoint.sh`)

- Copies vault from `/mnt/vault-source` to `/vault/$VAULT_BASENAME`
- Runs `git init`, `git add -A`, `git commit`
- Keeps container alive with `tail -f /dev/null`

### Main Script (`pi-vault.sh`)

- Bash script, expects bash 4+
- Uses Docker labels (`pi-vault=true`, `pi-vault-session=<id>`, etc.) for session tracking
- Session ID: first 8 chars of a UUID (via python3 or `/proc/sys/kernel/random/uuid`)
- Container naming: `pi-vault-<session_id>`
- Image name: `pi-vault` (single shared image across all sessions)

### Design Decisions

1. **Copy vs bind mount for vault**: We copy rather than bind-mount writable because (a) the source must stay untouched, and (b) git needs to operate on the files freely.
2. **Git repo created at runtime, not build time**: The vault contents change between sessions, so the repo is initialized by the entrypoint, not during `docker build`.
3. **Writeback via volume**: Rather than `docker cp`, writeback uses the already-mounted `/tmp/session` volume. This is simpler and avoids permission issues.
4. **No auto-writeback on stop**: Explicit writeback is required so users don't accidentally overwrite previous writeback data.

## Editing Guidelines

- Keep the script POSIX-compatible where possible, but bash 4+ features (like `[[ ]]`) are acceptable.
- All docker operations should handle the container not existing gracefully.
- Error messages should be prefixed with `[pi-vault]`.
- The Dockerfile should stay minimal — no unnecessary packages.
- Do not store secrets (bearer tokens) in any file, image layer, or label. They are only passed as runtime environment variables.
