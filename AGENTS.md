# AGENTS Guidelines for This Repository

This repository is a Python-only project with two runtime pieces:

- a FastAPI backend that owns HeatWave / MySQL access
- a Streamlit app in `heatwave_image_app.py`

When working in this repo as an agent, keep changes scoped to the Python application and deployment workflow.

## 1. Repository Boundaries

- The backend lives under `backend/`.
- The Streamlit app lives in `heatwave_image_app.py`.
- Tests live under `tests/`.
- Do not add macOS / Swift / Xcode project files back into this repository unless the user explicitly asks for that platform to return.
- If you change the backend API contract, update the Streamlit client in the same change.

## 2. Important Repository Paths

- `backend/`: FastAPI app, config, database access, image helpers, repository logic
- `tests/`: Python backend and Streamlit tests
- `tests/ui_support/mock_backend_server.py`: mock backend for UI-only local testing
- `heatwave_image_app.py`: Streamlit UI and local launcher entrypoint
- `sql/`: idempotent schema/table bootstrap SQL
- `scripts/deploy_to_vm.sh`: first-time Linux VM deployment helper
- `scripts/update_from_github.sh`: GitHub sync and restart helper for deployed instances
- `deploy/systemd/heatwave-image-intelligence.service`: VM service definition

## 3. Local Development Workflow

### Python setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env
```

### Full local app

```bash
.venv/bin/python heatwave_image_app.py
```

That path will start a local FastAPI backend automatically when the configured backend URL points at `127.0.0.1` or `localhost`.

### Backend only

```bash
.venv/bin/uvicorn backend.main:app --reload
```

### Streamlit only

```bash
.venv/bin/streamlit run heatwave_image_app.py
```

### UI-only local testing with the mock backend

```bash
.venv/bin/python tests/ui_support/mock_backend_server.py 8766 BluebonnetLonghorn.png
HEATWAVE_API_BASE_URL=http://127.0.0.1:8766 .venv/bin/streamlit run heatwave_image_app.py
```

## 4. Testing and Verification

- Full Python test suite:

```bash
.venv/bin/python -m pytest tests
```

- Quick syntax sanity check:

```bash
.venv/bin/python -m py_compile heatwave_image_app.py backend/*.py
```

Prefer targeted verification first, then broader tests when the change crosses backend and UI boundaries.

## 5. Environment and Secrets

- Runtime config comes from `.env`. Never commit `.env` or secrets.
- The Streamlit app stores only its backend URL locally in `~/.heatwave-image-intelligence/streamlit-settings.json`.
- Deployment-specific credentials stay on the target machine, not in git.

## 6. Deployment Notes

- The Linux VM flow uses `scripts/deploy_to_vm.sh` for first-time deployment and `scripts/update_from_github.sh` for in-place updates.
- The deployed VM currently runs the app stack with Python 3.9 in `.venv`. Keep backend and Streamlit runtime code compatible with Python 3.9 unless the deployment instructions are updated in the same change.
- After VM-facing backend or Streamlit changes, verify both:
  - the backend health endpoint on `127.0.0.1:8000`
  - the public Streamlit app on port `8501`

## 7. Git and Artifact Guardrails

- Do not stage or commit temporary folders such as `.playwright-cli/`, `tmp/`, `DerivedData/`, or other local debugging output unless the task explicitly requires them.
- Avoid destructive git commands.
- Keep the repository Python-only. If a change is unrelated to the Streamlit app, backend, tests, or deployment workflow, challenge it before adding files.
