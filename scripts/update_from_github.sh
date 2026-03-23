#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$REPO_ROOT"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

PYTHON_BIN="$(command -v python3.11 || command -v python3.10 || command -v python3.9 || command -v python3)"
"$PYTHON_BIN" -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

if command -v systemctl >/dev/null 2>&1 && sudo systemctl cat heatwave-image-intelligence >/dev/null 2>&1; then
  sudo systemctl restart heatwave-image-intelligence
fi

printf 'Repo synced to origin/%s and dependencies refreshed.\n' "$BRANCH"
