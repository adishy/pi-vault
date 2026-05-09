#!/bin/bash
set -euo pipefail

IMAGE_NAME="pi-vault"
CONTAINER_PREFIX="pi-vault"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") <vault_path> <bearer_token> [tmp_dir]
      Start a new PI vault session (container runs in background).
      tmp_dir defaults to /tmp.

  $(basename "$0") --stop <session_id>
      Stop and remove a session container.

  $(basename "$0") --writeback <session_id>
      Write current vault state (with .git) to the session tmp directory.

  $(basename "$0") --rebuild <vault_path> <bearer_token> [tmp_dir]
      Rebuild the Docker image, stop any running session, and start fresh.

  $(basename "$0") --list
      List active pi-vault sessions.

  $(basename "$0") --exec <session_id>
      Exec into the container and launch PI TUI.

Examples:
  ./pi-vault.sh ~/my-vault "tok_abc123"
  ./pi-vault.sh ~/my-vault "tok_abc123" /tmp
  ./pi-vault.sh --exec a1b2c3d4
  ./pi-vault.sh --writeback a1b2c3d4
  ./pi-vault.sh --stop a1b2c3d4
  ./pi-vault.sh --rebuild ~/my-vault "tok_abc123"
EOF
    exit 1
}

generate_session_id() {
    python3 -c "import uuid; print(str(uuid.uuid4())[:8])" 2>/dev/null \
        || cat /proc/sys/kernel/random/uuid | cut -d- -f1
}

build_image() {
    echo "[pi-vault] Building Docker image '${IMAGE_NAME}'..."
    docker build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"
    echo "[pi-vault] Image built successfully."
}

ensure_image() {
    if ! docker image inspect "${IMAGE_NAME}" &>/dev/null; then
        build_image
    fi
}

start_session() {
    local vault_path="$1"
    local bearer_token="$2"
    local tmp_dir="${3:-/tmp}"

    # Resolve vault path
    vault_path="$(cd "$vault_path" && pwd)"
    local vault_basename="$(basename "$vault_path")"

    # Generate session ID
    local session_id
    session_id="$(generate_session_id)"
    local container_name="${CONTAINER_PREFIX}-${session_id}"

    # Create session tmp directory on host
    local session_tmp="${tmp_dir}/${session_id}"
    mkdir -p "${session_tmp}"

    ensure_image

    echo "[pi-vault] Starting session: ${session_id}"
    echo "[pi-vault] Vault source: ${vault_path}"
    echo "[pi-vault] Session tmp:   ${session_tmp}"

    docker run -d \
        --name "${container_name}" \
        --label "pi-vault=true" \
        --label "pi-vault-session=${session_id}" \
        --label "pi-vault-source=${vault_path}" \
        --label "pi-vault-tmp=${session_tmp}" \
        -e "AWS_BEARER_TOKEN_BEDROCK=${bearer_token}" \
        -e "VAULT_BASENAME=${vault_basename}" \
        -v "${vault_path}:/mnt/vault-source:ro" \
        -v "${session_tmp}:/tmp/session" \
        "${IMAGE_NAME}" \
        >/dev/null

    # Wait for entrypoint to finish setup
    echo "[pi-vault] Waiting for vault initialization..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker logs "${container_name}" 2>&1 | grep -q "Vault ready"; then
            break
        fi
        sleep 1
        retries=$((retries - 1))
    done

    if [ $retries -eq 0 ]; then
        echo "[pi-vault] WARNING: Timed out waiting for vault init. Check logs:"
        echo "  docker logs ${container_name}"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Session ID:  ${session_id}"
    echo " Container:   ${container_name}"
    echo " Vault:       /vault/${vault_basename}"
    echo " Tmp (host):  ${session_tmp}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo " To launch PI:"
    echo "   docker exec -it ${container_name} bash -c 'cd /vault/${vault_basename} && pi'"
    echo ""
    echo " Or use shorthand:"
    echo "   ./pi-vault.sh --exec ${session_id}"
    echo ""
    echo " When done:"
    echo "   ./pi-vault.sh --writeback ${session_id}"
    echo "   ./pi-vault.sh --stop ${session_id}"
    echo ""
}

stop_session() {
    local session_id="$1"
    local container_name="${CONTAINER_PREFIX}-${session_id}"

    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "[pi-vault] Stopping and removing container: ${container_name}"
        docker stop "${container_name}" >/dev/null 2>&1 || true
        docker rm "${container_name}" >/dev/null 2>&1 || true
        echo "[pi-vault] Session ${session_id} stopped."
    else
        echo "[pi-vault] No container found for session: ${session_id}"
        exit 1
    fi
}

writeback_session() {
    local session_id="$1"
    local container_name="${CONTAINER_PREFIX}-${session_id}"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "[pi-vault] ERROR: Container ${container_name} is not running."
        exit 1
    fi

    # Get vault basename from container label
    local vault_source
    vault_source="$(docker inspect --format '{{index .Config.Labels "pi-vault-source"}}' "${container_name}")"
    local vault_basename="$(basename "$vault_source")"

    local session_tmp
    session_tmp="$(docker inspect --format '{{index .Config.Labels "pi-vault-tmp"}}' "${container_name}")"

    echo "[pi-vault] Writing back vault state to: ${session_tmp}/${vault_basename}"

    # Copy vault (with .git) to the session tmp volume from inside the container
    docker exec "${container_name}" bash -c \
        "cp -a /vault/${vault_basename} /tmp/session/${vault_basename}"

    echo "[pi-vault] Writeback complete."
    echo ""
    echo " Vault written to: ${session_tmp}/${vault_basename}"
    echo " To inspect changes:"
    echo "   cd ${session_tmp}/${vault_basename}"
    echo "   git status"
    echo "   git diff"
    echo ""
}

list_sessions() {
    echo "[pi-vault] Active sessions:"
    echo ""
    local found=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local cname status session_id vault_source
            cname="$(echo "$line" | awk '{print $1}')"
            status="$(echo "$line" | awk '{print $2}')"
            session_id="$(docker inspect --format '{{index .Config.Labels "pi-vault-session"}}' "$cname" 2>/dev/null)"
            vault_source="$(docker inspect --format '{{index .Config.Labels "pi-vault-source"}}' "$cname" 2>/dev/null)"
            printf "  %-12s %-10s %s\n" "${session_id}" "${status}" "${vault_source}"
            found=1
        fi
    done < <(docker ps -a --filter "label=pi-vault=true" --format "{{.Names}} {{.Status}}" 2>/dev/null)

    if [ $found -eq 0 ]; then
        echo "  (none)"
    fi
    echo ""
}

exec_session() {
    local session_id="$1"
    local container_name="${CONTAINER_PREFIX}-${session_id}"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "[pi-vault] ERROR: Container ${container_name} is not running."
        exit 1
    fi

    local vault_source
    vault_source="$(docker inspect --format '{{index .Config.Labels "pi-vault-source"}}' "${container_name}")"
    local vault_basename="$(basename "$vault_source")"

    echo "[pi-vault] Launching PI in session ${session_id}..."
    docker exec -it "${container_name}" bash -c "cd /vault/${vault_basename} && pi"
}

# ─── Main ────────────────────────────────────────────────────────────────────

if [ $# -eq 0 ]; then
    usage
fi

case "${1}" in
    --stop)
        [ $# -lt 2 ] && usage
        stop_session "$2"
        ;;
    --writeback)
        [ $# -lt 2 ] && usage
        writeback_session "$2"
        ;;
    --rebuild)
        shift
        [ $# -lt 2 ] && usage
        # Stop all running pi-vault containers
        echo "[pi-vault] Stopping all active sessions..."
        docker ps -q --filter "label=pi-vault=true" | xargs -r docker stop >/dev/null 2>&1 || true
        docker ps -aq --filter "label=pi-vault=true" | xargs -r docker rm >/dev/null 2>&1 || true
        # Rebuild image
        build_image
        # Start fresh session
        start_session "$@"
        ;;
    --list)
        list_sessions
        ;;
    --exec)
        [ $# -lt 2 ] && usage
        exec_session "$2"
        ;;
    --help|-h)
        usage
        ;;
    --*)
        echo "Unknown option: $1"
        usage
        ;;
    *)
        # Default: start session
        [ $# -lt 2 ] && usage
        start_session "$@"
        ;;
esac
