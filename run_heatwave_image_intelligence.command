#!/usr/bin/env bash

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: ./run_heatwave_image_intelligence.command [--mock-backend] [--built-app]

Starts the backend, waits for it to become healthy, and then launches the
macOS SwiftUI app. When the app exits, the backend is stopped.

Options:
  --mock-backend   Start the local mock backend instead of FastAPI/MySQL.
                   Useful for UI-only smoke tests and manual repros.
  --built-app      Launch the packaged app bundle from dist/ instead of
                   running the Swift package executable directly.

Requirements:
  - macOS with Swift / Xcode command line tools
  - a configured .env file with HeatWave / MySQL credentials for live mode
EOF
}

USE_MOCK_BACKEND=0
USE_BUILT_APP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --mock-backend)
      USE_MOCK_BACKEND=1
      ;;
    --built-app)
      USE_BUILT_APP=1
      ;;
    *)
      echo "Unknown argument: $1"
      echo
      show_help
      exit 1
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [[ "${USE_BUILT_APP}" == "1" ]]; then
  APP_PROCESS_NAME="HeatWaveImageIntelligenceMacApp"
else
  APP_PROCESS_NAME="HeatWaveImageIntelligenceMac"
fi
BACKEND_HOST="${HEATWAVE_BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${HEATWAVE_BACKEND_PORT:-8000}"
BACKEND_URL="http://${BACKEND_HOST}:${BACKEND_PORT}"
BACKEND_LOG="$(mktemp -t heatwave-image-intelligence-backend.XXXXXX.log)"
BACKEND_PID=""
RUN_STAMP=""
LAUNCH_SOURCE=""
PROMPT_LOG_PATH="${HEATWAVE_PROMPT_LOG_PATH:-}"
MOCK_IMAGE_PATH="${HEATWAVE_MOCK_IMAGE_PATH:-${SCRIPT_DIR}/BluebonnetLonghorn.png}"
APP_FIXTURE_IMAGE_PATH="${HEATWAVE_UI_TEST_IMAGE_PATH:-${MOCK_IMAGE_PATH}}"
APP_UPLOAD_NAME="${HEATWAVE_UI_TEST_UPLOAD_NAME:-Launcher Smoke Upload}"
BUILT_APP_PATH="${HEATWAVE_BUILT_APP_PATH:-${SCRIPT_DIR}/dist/HeatWave Image Intelligence.app}"
BUILT_APP_EXECUTABLE="${BUILT_APP_PATH}/Contents/MacOS/HeatWaveImageIntelligenceMacApp"

cleanup() {
  local exit_code=$?

  if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" >/dev/null 2>&1; then
    kill "${BACKEND_PID}" >/dev/null 2>&1 || true
    wait "${BACKEND_PID}" >/dev/null 2>&1 || true
  fi

  exit "${exit_code}"
}

require_command() {
  local command_name="$1"
  local install_hint="$2"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}"
    echo "${install_hint}"
    exit 1
  fi
}

ensure_venv() {
  if [[ ! -x ".venv/bin/python" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv .venv
  fi

  if ! .venv/bin/python -c "import fastapi, uvicorn" >/dev/null 2>&1; then
    echo "Installing Python dependencies..."
    .venv/bin/pip install -r requirements.txt
  fi
}

resolve_git_revision() {
  git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "nogit"
}

resolve_run_stamp() {
  if [[ -n "${HEATWAVE_BUILD_STAMP:-}" ]]; then
    echo "${HEATWAVE_BUILD_STAMP}"
    return 0
  fi

  local mode="live"
  if [[ "${USE_MOCK_BACKEND}" == "1" ]]; then
    mode="mock"
  fi

  local timestamp revision
  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  revision="$(resolve_git_revision)"
  echo "launcher-${mode}-${timestamp}-${revision}"
}

ensure_no_existing_app_instance() {
  if [[ "${HEATWAVE_ALLOW_EXISTING_APP:-0}" == "1" ]]; then
    return 0
  fi

  if pgrep -x "${APP_PROCESS_NAME}" >/dev/null 2>&1; then
    echo "${APP_PROCESS_NAME} is already running."
    echo "Quit the existing app first so this launcher does not attach you to an older session."
    echo "If you really want to reuse the running app, set HEATWAVE_ALLOW_EXISTING_APP=1."
    exit 1
  fi
}

wait_for_backend() {
  local attempts=30
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    if [[ -n "${BACKEND_PID}" ]] && ! kill -0 "${BACKEND_PID}" >/dev/null 2>&1; then
      echo "Backend exited before becoming ready."
      echo "Backend log: ${BACKEND_LOG}"
      tail -n 50 "${BACKEND_LOG}" || true
      return 1
    fi

    if curl -fsS "${BACKEND_URL}/health" >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
  done

  echo "Backend did not become ready at ${BACKEND_URL}."
  echo "Backend log: ${BACKEND_LOG}"
  tail -n 50 "${BACKEND_LOG}" || true
  return 1
}

start_backend() {
  if [[ "${USE_MOCK_BACKEND}" == "1" ]]; then
    if [[ ! -f "${MOCK_IMAGE_PATH}" ]]; then
      echo "Mock image fixture not found: ${MOCK_IMAGE_PATH}"
      exit 1
    fi

    echo "Starting mock backend at ${BACKEND_URL}..."
    python3 Tests/UITestSupport/mock_backend_server.py "${BACKEND_PORT}" "${MOCK_IMAGE_PATH}" >"${BACKEND_LOG}" 2>&1 &
  else
    echo "Starting backend at ${BACKEND_URL}..."
    .venv/bin/python -m uvicorn backend.main:app --host "${BACKEND_HOST}" --port "${BACKEND_PORT}" >"${BACKEND_LOG}" 2>&1 &
  fi

  BACKEND_PID=$!
}

launch_app() {
  if [[ "${USE_BUILT_APP}" == "1" ]]; then
    if [[ ! -x "${BUILT_APP_EXECUTABLE}" ]]; then
      echo "Built app not found: ${BUILT_APP_EXECUTABLE}"
      echo "Run scripts/build_macos_app.sh first, or set HEATWAVE_BUILT_APP_PATH."
      exit 1
    fi
  fi

  if [[ "${USE_MOCK_BACKEND}" == "1" ]]; then
    if [[ "${USE_BUILT_APP}" == "1" ]]; then
      HEATWAVE_API_BASE_URL="${BACKEND_URL}" \
      HEATWAVE_BUILD_STAMP="${RUN_STAMP}" \
      HEATWAVE_LAUNCH_SOURCE="${LAUNCH_SOURCE}" \
      HEATWAVE_PROMPT_LOG_PATH="${PROMPT_LOG_PATH}" \
      HEATWAVE_UI_TEST_IMAGE_PATH="${APP_FIXTURE_IMAGE_PATH}" \
      HEATWAVE_UI_TEST_UPLOAD_NAME="${APP_UPLOAD_NAME}" \
      "${BUILT_APP_EXECUTABLE}"
      return 0
    fi

    HEATWAVE_API_BASE_URL="${BACKEND_URL}" \
    HEATWAVE_BUILD_STAMP="${RUN_STAMP}" \
    HEATWAVE_LAUNCH_SOURCE="${LAUNCH_SOURCE}" \
    HEATWAVE_PROMPT_LOG_PATH="${PROMPT_LOG_PATH}" \
    HEATWAVE_UI_TEST_IMAGE_PATH="${APP_FIXTURE_IMAGE_PATH}" \
    HEATWAVE_UI_TEST_UPLOAD_NAME="${APP_UPLOAD_NAME}" \
    swift run HeatWaveImageIntelligenceMac
    return 0
  fi

  if [[ "${USE_BUILT_APP}" == "1" ]]; then
    HEATWAVE_API_BASE_URL="${BACKEND_URL}" \
    HEATWAVE_BUILD_STAMP="${RUN_STAMP}" \
    HEATWAVE_LAUNCH_SOURCE="${LAUNCH_SOURCE}" \
    HEATWAVE_PROMPT_LOG_PATH="${PROMPT_LOG_PATH}" \
    "${BUILT_APP_EXECUTABLE}"
    return 0
  fi

  HEATWAVE_API_BASE_URL="${BACKEND_URL}" \
  HEATWAVE_BUILD_STAMP="${RUN_STAMP}" \
  HEATWAVE_LAUNCH_SOURCE="${LAUNCH_SOURCE}" \
  HEATWAVE_PROMPT_LOG_PATH="${PROMPT_LOG_PATH}" \
  swift run HeatWaveImageIntelligenceMac
}

trap cleanup EXIT INT TERM

require_command "python3" "Install Python 3 and run this file again."
require_command "swift" "Install Xcode or the Xcode command line tools and run this file again."
require_command "curl" "Install curl and run this file again."

ensure_no_existing_app_instance

if [[ "${USE_MOCK_BACKEND}" != "1" ]]; then
  if [[ ! -f ".env" ]]; then
    cp .env.example .env
    echo "Created .env from .env.example."
    echo "Fill in your HeatWave / MySQL settings in ${SCRIPT_DIR}/.env, then run this file again."
    exit 1
  fi

  ensure_venv
fi

RUN_STAMP="$(resolve_run_stamp)"

if [[ "${USE_BUILT_APP}" == "1" && "${USE_MOCK_BACKEND}" == "1" ]]; then
  LAUNCH_SOURCE="${HEATWAVE_LAUNCH_SOURCE:-run_heatwave_image_intelligence.command --mock-backend --built-app}"
elif [[ "${USE_BUILT_APP}" == "1" ]]; then
  LAUNCH_SOURCE="${HEATWAVE_LAUNCH_SOURCE:-run_heatwave_image_intelligence.command --built-app}"
elif [[ "${USE_MOCK_BACKEND}" == "1" ]]; then
  LAUNCH_SOURCE="${HEATWAVE_LAUNCH_SOURCE:-run_heatwave_image_intelligence.command --mock-backend}"
else
  LAUNCH_SOURCE="${HEATWAVE_LAUNCH_SOURCE:-run_heatwave_image_intelligence.command}"
fi

start_backend
wait_for_backend

if [[ "${USE_MOCK_BACKEND}" == "1" ]]; then
  echo "Mock backend is healthy."
else
  echo "Backend is healthy."
fi
echo "Backend log: ${BACKEND_LOG}"
echo "Run stamp: ${RUN_STAMP}"
echo "Launch source: ${LAUNCH_SOURCE}"
if [[ -n "${PROMPT_LOG_PATH}" ]]; then
  echo "Prompt log: ${PROMPT_LOG_PATH}"
fi
if [[ "${USE_BUILT_APP}" == "1" ]]; then
  echo "Launching packaged macOS app bundle. Closing the app will stop the backend."
else
  echo "Launching macOS app. Closing the app will stop the backend."
fi

launch_app
