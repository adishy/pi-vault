#!/bin/bash
set -e

VAULT_BASENAME="${VAULT_BASENAME:-vault}"

# Copy vault from mounted source to working directory
if [ -d "/mnt/vault-source" ]; then
    cp -a /mnt/vault-source "/vault/${VAULT_BASENAME}"
    cd "/vault/${VAULT_BASENAME}"

    # Initialize git repo and commit all files
    git init
    git config user.email "pi-vault@container"
    git config user.name "PI Vault"
    git add -A
    git commit -m "Initial commit: vault snapshot at $(date -Iseconds)" --allow-empty
    echo "[entrypoint] Git repo initialized with $(git log --oneline | wc -l) commit(s), $(git ls-files | wc -l) files tracked."
else
    echo "[entrypoint] ERROR: No vault source mounted at /mnt/vault-source"
    exit 1
fi

echo "[entrypoint] Vault ready at /vault/${VAULT_BASENAME}"
echo "[entrypoint] Container running. Use 'docker exec -it <container> pi' to start PI."

# Keep container alive
exec tail -f /dev/null
