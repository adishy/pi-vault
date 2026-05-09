# PI Vault Runner

Run the [PI mono agent harness](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) in an isolated Docker container against a copy of your Obsidian vault (or any directory). Changes are tracked via an auto-created git repo inside the container, and can be written back to a host-accessible tmp directory for review.

## Motivation

You want an AI coding agent to read, edit, and create files in your vault — but you don't want it touching your real files directly. This tool:

1. Copies your vault into a disposable container at startup
2. Commits the initial state to a fresh git repo
3. Lets you run PI interactively inside the container
4. When you're done, writes the modified vault (with `.git/`) to a tmp directory so you can `git diff` to see exactly what changed before merging anything back

## Prerequisites

- Docker
- Bash 4+
- An AWS Bedrock bearer token (set as `AWS_BEARER_TOKEN_BEDROCK` inside the container)

## Quick Start

```bash
# 1. Start a session (auto-attaches to PI in tmux)
./pi-vault.sh ~/my-obsidian-vault "your-bearer-token"

# 2. Work with PI... detach with Ctrl-b d when you need to step away

# 3. Reattach later
./pi-vault.sh --start a1b2c3d4

# 4. When done, write back and inspect changes
./pi-vault.sh --writeback a1b2c3d4
cd /tmp/a1b2c3d4/my-obsidian-vault
git status
git diff

# 5. Stop the session
./pi-vault.sh --stop a1b2c3d4
```

## CLI Reference

```
pi-vault.sh <vault_path> <bearer_token> [tmp_dir]
```

Start a new session. Builds the Docker image if it doesn't exist, generates a random session ID, copies the vault into the container, creates a git repo, starts PI in a tmux session, and attaches.

Use **Ctrl-b d** to detach from tmux while keeping PI running.

| Argument | Description | Default |
|----------|-------------|---------|
| `vault_path` | Path to your vault / directory | (required) |
| `bearer_token` | AWS Bedrock bearer token | (required) |
| `tmp_dir` | Host directory for session output | `/tmp` |

---

```
pi-vault.sh --start <session_id>
```

Reattach to an existing session's tmux. If PI has exited, starts a fresh PI instance in a new tmux session.

---

```
pi-vault.sh --writeback <session_id>
```

Copy the current vault state (including the `.git/` directory) from the container to `<tmp_dir>/<session_id>/<vault-basename>` on the host. This lets you run `git status` and `git diff` to review all changes made during the session.

---

```
pi-vault.sh --stop <session_id>
```

Stop and remove the container for a given session. Does **not** automatically write back — run `--writeback` first if you want to preserve changes.

---

```
pi-vault.sh --rebuild <vault_path> <bearer_token> [tmp_dir]
```

Stops all active pi-vault containers, rebuilds the Docker image from scratch (picking up any Dockerfile/entrypoint changes), then starts a fresh session.

---

```
pi-vault.sh --list
```

List all active and stopped pi-vault sessions with their status and source vault path.

---

```
pi-vault.sh --help
```

Print usage information.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Host                                               │
│                                                     │
│  ~/vault (read-only mount) ──┐                      │
│                              ▼                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  Container: pi-vault-<session_id>           │    │
│  │                                             │    │
│  │  /mnt/vault-source (ro) ─── cp ──►         │    │
│  │  /vault/<basename>/    ← git init + commit  │    │
│  │                                             │    │
│  │  PI runs here, edits files freely           │    │
│  │                                             │    │
│  │  /tmp/session/ ──────────────────────────┐  │    │
│  └──────────────────────────────────────────┼──┘    │
│                                             ▼       │
│  <tmp_dir>/<session_id>/   (volume mount)           │
│      └── <basename>/       (after --writeback)      │
│           ├── .git/                                 │
│           ├── file1.md                              │
│           └── ...                                   │
└─────────────────────────────────────────────────────┘
```

## Notes

- The source vault is **never modified** — it's mounted read-only.
- Multiple sessions can run concurrently, each with a unique session ID.
- The container stays alive via `tail -f /dev/null` even when detached from tmux.
- PI runs inside a tmux session named `pi` — detach with Ctrl-b d, reattach with `--start`.
- PI picks up the Bedrock token from the `AWS_BEARER_TOKEN_BEDROCK` environment variable.
- The git repo inside the container has a single initial commit with all vault files — any subsequent changes by PI show up as uncommitted modifications in `git diff`.
