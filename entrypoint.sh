#!/bin/bash
set -e

VAULT_BASENAME="${VAULT_BASENAME:-vault}"

# Copy vault from mounted source to working directory
if [ -d "/mnt/vault-source" ]; then
    cp -a /mnt/vault-source "/vault/${VAULT_BASENAME}"
    cd "/vault/${VAULT_BASENAME}"

    # Initialize git repo and commit all files
    git config --global init.defaultBranch main
    git config --global user.email "pi-vault@container"
    git config --global user.name "PI Vault"
    git config --global --add safe.directory /vault/adishy-core
    git init
    git add -A
    git commit -m "Initial commit: vault snapshot at $(date -Iseconds)" --allow-empty
    echo "[entrypoint] Git repo initialized with $(git log --oneline | wc -l) commit(s), $(git ls-files | wc -l) files tracked."
else
    echo "[entrypoint] ERROR: No vault source mounted at /mnt/vault-source"
    exit 1
fi

# Set up pi session directory
export PI_CODING_AGENT_SESSION_DIR="/vault/.pi-sessions"
mkdir -p "$PI_CODING_AGENT_SESSION_DIR"

# Generate session-specific theme for visual distinction
PI_CONFIG_DIR="${HOME}/.pi/agent"
mkdir -p "${PI_CONFIG_DIR}/themes"
if [ -n "${PI_VAULT_SESSION_ID}" ]; then
    /generate-theme.sh "${PI_VAULT_SESSION_ID}" "${PI_CONFIG_DIR}/themes/pi-vault-session.json"
    # Write settings to use the generated theme
    mkdir -p "${PI_CONFIG_DIR}"
    echo '{"theme":"pi-vault-'"${PI_VAULT_SESSION_ID}"'"}' > "${PI_CONFIG_DIR}/settings.json"
    echo "[entrypoint] Theme generated for session ${PI_VAULT_SESSION_ID} (hue-shifted)"
fi

echo "[entrypoint] Vault ready at /vault/${VAULT_BASENAME}"

# Configure tmux (session will be started when user attaches)
mkdir -p ~/.tmux
cat > ~/.tmux.conf <<'EOF'
# High scrollback buffer
set-option -g history-limit 100000

# Resize to current client when attaching
set-option -g aggressive-resize on

# Disable tmux status bar entirely - gives full screen to TUI
set-option -g status off

# Ensure alternate screen buffer works properly
set-option -g alternate-screen on

# Proper terminal support
set-option -g default-terminal "screen-256color"

# Help with terminal size detection
set-option -g focus-events on
EOF

echo "[entrypoint] Waiting for user to attach..."

# Keep container alive - tmux+PI started when user attaches (gets correct terminal size)
exec tail -f /dev/null
