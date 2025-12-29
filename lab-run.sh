#!/usr/bin/env bash
set -euo pipefail

# lab-run.sh — helper to run the lab locally with LocalStack
# Usage: ./lab-run.sh [--apply] [--tool=terraform|tofu]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# prefer modern `docker compose` but fall back to `docker-compose`
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
else
  DOCKER_COMPOSE_CMD="docker-compose"
fi

APPLY=false
DESTROY=false
TOOL="${TOOL:-terraform}"

# LocalStack runtime options
MAIN_CONTAINER_NAME="${MAIN_CONTAINER_NAME:-localstack-main}"
LOCALSTACK_WAIT_TIMEOUT="${LOCALSTACK_WAIT_TIMEOUT:-60}"
LOCALSTACK_HEALTH_URL="${LOCALSTACK_HEALTH_URL:-http://localhost:4566/_localstack/health}"

# Parse args (supports --apply and --tool=NAME)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
      ;;
    --tool=*)
      TOOL="${1#--tool=}"
      shift
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --destroy)
      DESTROY=true
      shift
      ;;
    *)
      echo "Warning: unknown arg '$1' - ignoring"
      shift
      ;;
  esac
done

echo "Using tool: $TOOL"

echo "Starting LocalStack (container name: ${MAIN_CONTAINER_NAME})..."
$DOCKER_COMPOSE_CMD up -d

# Ensure local override services (ec2-node-1, minio, mailhog) are started
$DOCKER_COMPOSE_CMD up -d ec2-node-1 minio mailhog || true

echo "Waiting for LocalStack to be ready (timeout ${LOCALSTACK_WAIT_TIMEOUT}s)..."

# If localstack CLI is available, use its `wait` command which is robust
if command -v localstack >/dev/null 2>&1; then
  echo "Detected localstack CLI — using 'localstack wait'"
  if ! localstack wait --timeout "$LOCALSTACK_WAIT_TIMEOUT" >/dev/null 2>&1; then
    echo "localstack wait timed out or failed. Showing recent logs."
    $DOCKER_COMPOSE_CMD logs --no-color --tail=200 "$MAIN_CONTAINER_NAME" || true
    exit 1
  fi
  echo "LocalStack is ready (via localstack CLI)."
else
  # Fallback: poll health endpoint. Try jq if available for safer JSON probing.
  USE_JQ=false
  if command -v jq >/dev/null 2>&1; then
    USE_JQ=true
  fi

  start_ts=$(date +%s)
  while :; do
    if curl -fsS "$LOCALSTACK_HEALTH_URL" -m 5 >/tmp/.localstack_health.json 2>/dev/null; then
      if $USE_JQ; then
        if jq -e '.services' /tmp/.localstack_health.json >/dev/null 2>&1; then
          echo "LocalStack is ready (health endpoint)."
          break
        fi
      else
        if grep -q '"services"' /tmp/.localstack_health.json; then
          echo "LocalStack is ready (health endpoint)."
          break
        fi
      fi
    fi

    now=$(date +%s)
    if [ $((now - start_ts)) -ge "$LOCALSTACK_WAIT_TIMEOUT" ]; then
      echo "Timed out waiting for LocalStack health. Showing recent logs."
      $DOCKER_COMPOSE_CMD logs --no-color --tail=200 "$MAIN_CONTAINER_NAME" || true
      exit 1
    fi
    echo "  waiting for health... ($(date -u -d @$((now - start_ts)) +%M:%S) elapsed)"
    sleep 2
  done

  # keep /tmp/.localstack_health.json for later service detection

# ----- detect available LocalStack services and print a summary -----
LOCALSTACK_HEALTH_FILE="/tmp/.localstack_health.json"
if [ ! -f "$LOCALSTACK_HEALTH_FILE" ]; then
  if ! curl -fsS "$LOCALSTACK_HEALTH_URL" -m 5 >"$LOCALSTACK_HEALTH_FILE" 2>/dev/null; then
    echo "Could not fetch LocalStack health for service detection. Skipping summary."
  fi
fi

print_localstack_services() {
  file="$1"
  echo "Detected LocalStack services summary:"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.services | to_entries[] | "- \(.key): \(.value.status // \"unknown\")"' "$file" || true
    echo
    # show any non-running services
    nonrunning=$(jq -r '.services | to_entries[] | select(.value.status != "running") | .key' "$file" 2>/dev/null || true)
    if [ -n "$nonrunning" ]; then
      echo "Warning: some services are not 'running':"
      echo "$nonrunning" | sed 's/^/  - /'
    fi
  elif command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import json,sys
try:
    j=json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
services=j.get('services',{})
for k,v in services.items():
    print(f"- {k}: {v.get('status','unknown')}")
non=[k for k,v in services.items() if v.get('status')!='running']
if non:
    print('\nWarning: some services are not \'running\':')
    for n in non:
        print('  - '+n)
PY
  else
    # last-resort simple grep/awk parser (best-effort)
    grep -o '"[a-z0-9_-]\+"\s*:\s*{[^}]*"status"\s*:\s*"[^"]\+"' "$file" 2>/dev/null | \
      sed -E 's/"([a-z0-9_-]+)"\s*:\s*\{[^}]*"status"\s*:\s*"([^"]+)"/ - \1: \2/' || true
  fi
}

if [ -f "$LOCALSTACK_HEALTH_FILE" ]; then
  print_localstack_services "$LOCALSTACK_HEALTH_FILE"
  rm -f "$LOCALSTACK_HEALTH_FILE"
fi


export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export TF_VAR_use_local=${TF_VAR_use_local:-true}

# If running locally, export bastion/container info for Terraform and wait for SSH
if [ "${TF_VAR_use_local:-false}" = "true" ]; then
  export TF_VAR_bastion_host=${TF_VAR_bastion_host:-127.0.0.1}
  export TF_VAR_bastion_ssh_port=${TF_VAR_bastion_ssh_port:-2222}

  # generate a local SSH keypair for automatic injection if missing
  SSH_KEY_DIR="${SSH_KEY_DIR:-$SCRIPT_DIR/.local/ssh}"
  SSH_PRIVATE_KEY_PATH="$SSH_KEY_DIR/id_rsa"
  SSH_PUBLIC_KEY_PATH="$SSH_PRIVATE_KEY_PATH.pub"
  mkdir -p "$SSH_KEY_DIR"
  if [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
    echo "Generating SSH keypair for local EC2 container at $SSH_PRIVATE_KEY_PATH"
    ssh-keygen -t rsa -b 2048 -f "$SSH_PRIVATE_KEY_PATH" -N "" -C "local-ec2" >/dev/null 2>&1 || true
    chmod 600 "$SSH_PRIVATE_KEY_PATH" || true
  fi

  # export TF var pointing to the private key file so Terraform can use it
  export TF_VAR_ssh_private_key_path=${TF_VAR_ssh_private_key_path:-$SSH_PRIVATE_KEY_PATH}

  # inject the public key into the container's root authorized_keys (best-effort)
  if docker ps --format '{{.Names}}' | grep -q '^ec2-node-1$'; then
    if [ -f "$SSH_PUBLIC_KEY_PATH" ]; then
      echo "Injecting public key into ec2-node-1 container"
      # ensure .ssh exists and append the key atomically
      docker exec -i ec2-node-1 bash -lc 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && cat >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys' < "$SSH_PUBLIC_KEY_PATH" || true
    else
      echo "Public SSH key not found at $SSH_PUBLIC_KEY_PATH; skipping injection"
    fi
  else
    echo "ec2-node-1 container not running; skipping key injection"
  fi

  echo "Using local bastion at ${TF_VAR_bastion_host}:${TF_VAR_bastion_ssh_port}"

  # wait for SSH port to be open (use nc if available, fallback to /dev/tcp)
  SSH_WAIT_TIMEOUT=${SSH_WAIT_TIMEOUT:-60}
  start_ts=$(date +%s)
  while :; do
    if command -v nc >/dev/null 2>&1; then
      if nc -z "$TF_VAR_bastion_host" "$TF_VAR_bastion_ssh_port" >/dev/null 2>&1; then
        echo "Bastion SSH is reachable"
        break
      fi
    else
      if (echo > /dev/tcp/${TF_VAR_bastion_host}/${TF_VAR_bastion_ssh_port}) >/dev/null 2>&1; then
        echo "Bastion SSH is reachable"
        break
      fi
    fi

    now=$(date +%s)
    if [ $((now - start_ts)) -ge "$SSH_WAIT_TIMEOUT" ]; then
      echo "Timed out waiting for bastion SSH on ${TF_VAR_bastion_host}:${TF_VAR_bastion_ssh_port}"
      break
    fi
    sleep 1
  done
fi

# Build the TF command that will run inside Make (supports terraform or tofu)
TF_CMD="$TOOL -chdir=core"

echo "Initializing Terraform/Tofu in core/..."
make TF="$TF_CMD" init

echo "Planning Terraform/Tofu in core/..."
make TF="$TF_CMD" plan

if [ "$APPLY" = true ]; then
  echo "Applying Terraform/Tofu in core/..."
  make TF="$TF_CMD" apply
else
  echo "Plan complete. To apply run: ./lab-run.sh --apply"
fi

if [ "$DESTROY" = true ]; then
  echo "Destroying infrastructure via Terraform/Tofu in core/..."
  make TF="$TF_CMD" destroy
fi

echo "Done."
