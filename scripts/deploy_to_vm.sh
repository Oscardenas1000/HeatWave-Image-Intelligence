#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy_to_vm.sh --host opc@1.2.3.4 --key /path/to/key.pem --remote-dir /home/opc/heatwave-image-intelligence

Notes:
  - Excludes .venv, .git, __pycache__, and .env from transfer.
  - Installs Python dependencies on the remote host.
  - Does not create secrets; copy .env.example to .env on the VM and fill it in separately.
EOF
}

HOST=""
KEY_PATH=""
REMOTE_DIR=""
SSH_PORT="22"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --key)
      KEY_PATH="$2"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="$2"
      shift 2
      ;;
    --port)
      SSH_PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" || -z "$KEY_PATH" || -z "$REMOTE_DIR" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SSH_OPTS=(-i "$KEY_PATH" -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new)
RSYNC_SSH="ssh"

for opt in "${SSH_OPTS[@]}"; do
  RSYNC_SSH+=" $(printf '%q' "$opt")"
done

ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p '$REMOTE_DIR'"

rsync -az --delete \
  -e "$RSYNC_SSH" \
  --exclude '.git/' \
  --exclude '.venv/' \
  --exclude '__pycache__/' \
  --exclude '.env' \
  --exclude '*.base64.txt' \
  --exclude '*.pyc' \
  "$REPO_ROOT/" "$HOST:$REMOTE_DIR/"

ssh "${SSH_OPTS[@]}" "$HOST" "
  set -euo pipefail
  cd '$REMOTE_DIR'
  PYTHON_BIN=\$(command -v python3.11 || command -v python3.10 || command -v python3.9 || command -v python3)
  \"\$PYTHON_BIN\" -m venv .venv
  . .venv/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt
  printf '\nDeployment finished.\n'
  printf 'Next: cp .env.example .env && edit the values.\n'
  printf 'Then: .venv/bin/python heatwave_image_app.py\n'
"
