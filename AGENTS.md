# AGENTS Guidelines for This Repository

This repository contains three app surfaces for the same product:

- a native macOS SwiftUI client
- a FastAPI backend that owns HeatWave / MySQL access
- a Streamlit fallback app that talks to the same backend

When working in this repo as an agent, prefer the smallest change that solves the task while keeping those surfaces aligned.

## 1. Respect the App Boundaries

- Swift code lives under `Sources/` and `Package.swift`.
- The backend lives under `backend/`.
- The Streamlit fallback lives in `heatwave_image_app.py`.
- Do not change Swift files unless the task explicitly requires Swift work.
- If you change the backend API contract, update every affected client intentionally. Both the macOS app and the Streamlit app depend on the FastAPI responses.

## 2. Important Repository Paths

- `backend/`: FastAPI app, config, database access, image helpers, repository logic
- `Sources/HeatWaveImageClientCore/`: shared Swift models, API client, settings, and view models
- `Sources/HeatWaveImageIntelligenceMac/`: SwiftUI macOS app
- `tests/`: Python backend and Streamlit tests
- `tests/UITestSupport/mock_backend_server.py`: mock backend for UI-only testing
- `run_heatwave_image_intelligence.command`: starts the backend and launches the macOS app together
- `scripts/deploy_to_vm.sh`: copy-and-bootstrap deployment helper for Linux VMs
- `scripts/update_from_github.sh`: pull latest GitHub changes on a VM and refresh the Python environment
- `deploy/systemd/heatwave-image-intelligence.service`: VM service definition
- `sql/`: idempotent schema/table bootstrap SQL

## 3. Local Development Workflow

### Python setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env
```

### Backend only

```bash
.venv/bin/uvicorn backend.main:app --reload
```

### Streamlit fallback

```bash
.venv/bin/python heatwave_image_app.py
```

Or:

```bash
.venv/bin/streamlit run heatwave_image_app.py
```

### Native macOS app

```bash
swift run HeatWaveImageIntelligenceMac
```

### Combined launcher

```bash
./run_heatwave_image_intelligence.command
```

For UI-only testing against the bundled mock backend:

```bash
./run_heatwave_image_intelligence.command --mock-backend
```

## 4. Testing and Verification

- Python tests:

```bash
.venv/bin/python -m pytest tests
```

- Swift tests:

```bash
swift test
```

- Launcher smoke test:

```bash
python3 scripts/smoke_test_launcher.py
```

- For targeted Python changes, `py_compile` is a good quick sanity check:

```bash
.venv/bin/python -m py_compile heatwave_image_app.py backend/*.py
```

Prefer targeted verification first, then broader suites if the change crosses boundaries.

## 5. Environment and Secret Handling

- Runtime config comes from `.env`. Do not commit `.env` or any secret material.
- The Streamlit app stores only its backend URL locally in `~/.heatwave-image-intelligence/streamlit-settings.json`.
- Generated local artifacts should stay untracked unless a task explicitly requires them.

## 6. Deployment Notes

- The Linux VM flow uses `scripts/deploy_to_vm.sh` for first-time deployment and `scripts/update_from_github.sh` for in-place updates.
- The deployed VM currently runs the app stack with Python 3.9 in `.venv`. Keep backend and Streamlit runtime code compatible with Python 3.9 unless the deployment instructions are updated in the same change.
- After VM-facing backend or Streamlit changes, verify both:
  - the backend health endpoint on `127.0.0.1:8000`
  - the public Streamlit app on port `8501`

## 7. Git and Artifact Guardrails

- Do not stage or commit temporary folders such as `.playwright-cli/`, `tmp/`, `DerivedData/`, or other local debugging output unless the task explicitly requires them.
- Avoid destructive git commands.
- Keep changes scoped. If the task is Streamlit-only or backend-only, leave the Swift app untouched.
