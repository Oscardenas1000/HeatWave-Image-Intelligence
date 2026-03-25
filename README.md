# HeatWave Image Intelligence

HeatWave Image Intelligence now includes three app surfaces:

- a native `macOS` SwiftUI client
- a `FastAPI` backend that owns HeatWave / MySQL access
- the original `Streamlit` app kept as a fallback reference

The core workflow is the same across the app surfaces:

- uploading images into Oracle HeatWave as base64 payloads
- browsing a searchable image library
- asking HeatWave AI to describe or analyze a selected image with `sys.ML_GENERATE`

## Project layout

- `backend/`: FastAPI service, shared config/bootstrap/database logic, and API routes
- `Sources/HeatWaveImageClientCore/`: shared Swift models, API client, settings, and view models
- `Sources/HeatWaveImageIntelligenceMac/`: native macOS SwiftUI app
- `Tests/HeatWaveImageClientCoreTests/`: Swift unit tests for the client and view models
- `tests/`: Python backend tests
- `Package.swift`: Swift package manifest for the macOS app
- `heatwave_image_app.py`: original Streamlit application
- `img_to_base64.py`: helper that converts an image file into a base64 text file
- `requirements.txt`: Python dependencies
- `.env.example`: required runtime configuration template
- `sql/`: idempotent schema bootstrap files applied at app startup
- `scripts/deploy_to_vm.sh`: repeatable Linux VM deployment helper
- `scripts/update_from_github.sh`: pulls the latest GitHub state and refreshes the VM install
- `deploy/systemd/heatwave-image-intelligence.service`: optional systemd unit for long-running VM hosting

## Prerequisites

- Python 3.9+
- Swift 6.2 / Xcode 16+ on macOS
- network access to your HeatWave / MySQL instance
- a database user that can create and read the target schema and table
- HeatWave `ML_GENERATE` access for image-aware prompts

## Quick start

1. Create a virtual environment and install Python dependencies.

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

2. Create your local config file.

```bash
cp .env.example .env
```

3. Edit `.env` with your HeatWave connection details.

```dotenv
DB_HOST=your-heatwave-host
DB_PORT=3306
DB_USER=your-db-user
DB_PASSWORD=your-db-password
DB_SCHEMA=image_registry
DB_TABLE=image_assets
AI_MODEL_ID=google.gemini-2.5-pro
AI_LANGUAGE=en
```

4. Run the FastAPI backend.

```bash
.venv/bin/uvicorn backend.main:app --reload
```

5. In a second terminal, launch the native macOS app.

```bash
swift run HeatWaveImageIntelligenceMac
```

The macOS app defaults to `http://127.0.0.1:8000` for the backend URL. You can change that later in app settings, and the app stores only that URL locally.

## One-file launcher

If you want one file that starts both the backend and the macOS app, run:

```bash
./run_heatwave_image_intelligence.command
```

The launcher will:

- create `.venv` if it does not exist yet
- install Python requirements if needed
- start the FastAPI backend on `127.0.0.1:8000`
- wait for `GET /health` to succeed
- launch the SwiftUI macOS app with that backend URL
- stop the backend automatically after the app exits

If `.env` is missing, the launcher will create it from `.env.example` and stop so you can fill in your database credentials first.

For UI-only testing without touching FastAPI/MySQL, launch the app against the bundled mock backend:

```bash
./run_heatwave_image_intelligence.command --mock-backend
```

That path uses the same SwiftUI app launcher, injects a visible run stamp into the UI, and exposes the bundled `BluebonnetLonghorn.png` as the "Use Test Image" fixture in the upload sheet.

## Streamlit fallback

The original Streamlit app is still available:

```bash
.venv/bin/python heatwave_image_app.py
```

You can also run it directly with:

```bash
.venv/bin/streamlit run heatwave_image_app.py
```

The Streamlit fallback now talks to the same FastAPI backend as the native macOS app. It defaults to `http://127.0.0.1:8000`, stores only that backend URL locally, and honors `HEATWAVE_API_BASE_URL` when you want to override the default at launch time.

## Backend API

The FastAPI service exposes:

- `GET /health`
- `GET /app-info`
- `GET /images?search=...`
- `GET /images/{id}`
- `GET /images/{id}/content`
- `POST /images`
- `POST /images/{id}/insights`

## What the backend creates

At startup, the app ensures that the target schema and table exist. By default, it uses:

- schema: `image_registry`
- table: `image_assets`

Each stored image record includes the image name, original filename, MIME type, base64 payload, and timestamps.

At startup, the backend reads the ordered SQL files in `sql/` and applies them with `CREATE ... IF NOT EXISTS`, so a fresh HeatWave instance is initialized automatically and an existing one is skipped safely.

## Testing

Run the backend tests with:

```bash
.venv/bin/python -m pytest tests
```

Run the Swift client build and tests with:

```bash
swift build
swift test
```

Build a standalone macOS app bundle with icon assets and embedded frameworks:

```bash
bash scripts/build_macos_app.sh
```

That produces:

```text
dist/HeatWave Image Intelligence.app
```

To run the packaged app bundle against the backend launcher flow instead of `swift run`, use:

```bash
./run_heatwave_image_intelligence.command --built-app
```

Or for a UI-only bundle repro against the mock backend:

```bash
./run_heatwave_image_intelligence.command --mock-backend --built-app
```

Run the launcher-path smoke test with:

```bash
python3 scripts/smoke_test_launcher.py
```

That smoke test launches the same `./run_heatwave_image_intelligence.command --mock-backend` entrypoint you use manually, waits for the backend health/app-info endpoints, confirms the launcher log run stamp, and verifies that the macOS app window appears. It requires macOS Accessibility permissions for Terminal / `osascript`.

Use the smoke test to validate the real launcher path. Use `swift test` and the Xcode macOS test target for upload, prompt entry, and insight-generation behavior.

To smoke-test the packaged `.app` bundle instead of the package executable, run:

```bash
python3 scripts/smoke_test_launcher.py --built-app
```

For manual launcher repros, compare the run stamp shown in the sidebar or in Settings -> Runtime Diagnostics with the stamp printed in the launcher output. That tells you whether you are looking at the same launched session the automation just exercised.

If you need prompt-input diagnostics for a manual repro, run:

```bash
HEATWAVE_PROMPT_LOG_PATH=/tmp/heatwave-prompt.log ./run_heatwave_image_intelligence.command --mock-backend
```

The prompt editor will append focus, key, and text-change events to that log file so you can compare what the app actually received.

## VM deployment

For a Linux VM, use the included deployment helper:

```bash
scripts/deploy_to_vm.sh \
  --host opc@YOUR_VM_IP \
  --key /path/to/ssh-key.pem \
  --remote-dir /home/opc/heatwave-image-intelligence
```

After the copy finishes on the VM:

```bash
cd /home/opc/heatwave-image-intelligence
cp .env.example .env
vi .env
.venv/bin/python heatwave_image_app.py
```

To run it as a service on boot:

```bash
sudo cp deploy/systemd/heatwave-image-intelligence.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now heatwave-image-intelligence
sudo systemctl status heatwave-image-intelligence
```

To pull the latest GitHub changes onto an instance and restart the app:

```bash
scripts/update_from_github.sh
```

If the VM does not already have a modern Python installed, install one first. On Oracle Linux / RHEL that is typically:

```bash
sudo dnf install -y python39 python39-pip
```

## Utility helper

To generate a base64 text file from an image:

```bash
python3 img_to_base64.py path/to/image.png
```

To include a `data:` URL prefix:

```bash
python3 img_to_base64.py --data-url path/to/image.png
```

## Notes

- Secrets are intentionally not committed. Use `.env` for local or VM-specific credentials.
- The app validates required environment variables at startup and will stop with a clear error if they are missing.
- Generated `.base64.txt` files are ignored by git because they can be recreated with `img_to_base64.py`.
