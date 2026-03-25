# HeatWave Image Intelligence

HeatWave Image Intelligence is now a Python-only project with two runtime pieces:

- a `FastAPI` backend that owns HeatWave / MySQL access
- a `Streamlit` app for uploading, browsing, describing, and analyzing images

The core workflow is:

- upload images into Oracle HeatWave as base64 payloads
- browse a searchable image library
- generate reusable descriptions and focused insights with `sys.ML_GENERATE`

## Project layout

- `backend/`: FastAPI service, shared config/bootstrap/database logic, and API routes
- `tests/`: Python backend and Streamlit tests
- `tests/ui_support/mock_backend_server.py`: mock backend for UI-only local testing
- `heatwave_image_app.py`: Streamlit application
- `requirements.txt`: Python dependencies
- `.env.example`: required runtime configuration template
- `sql/`: idempotent schema bootstrap files applied at app startup
- `scripts/deploy_to_vm.sh`: repeatable Linux VM deployment helper
- `scripts/update_from_github.sh`: pulls the latest GitHub state and refreshes the VM install
- `deploy/systemd/heatwave-image-intelligence.service`: optional systemd unit for long-running VM hosting
- `img_to_base64.py`: helper that converts an image file into a base64 text file

## Prerequisites

- Python 3.9+
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

4. Start the app.

```bash
.venv/bin/python heatwave_image_app.py
```

That entrypoint will ensure dependencies exist, start a local FastAPI backend when the configured backend URL points at `127.0.0.1` or `localhost`, and then launch Streamlit.

If you want to run the backend separately:

```bash
.venv/bin/uvicorn backend.main:app --reload
```

You can also run Streamlit directly:

```bash
.venv/bin/streamlit run heatwave_image_app.py
```

The app defaults to `http://127.0.0.1:8000`, stores only that backend URL locally, and honors `HEATWAVE_API_BASE_URL` when you want to override the default at launch time.

## UI-only local testing

To work on the Streamlit interface without touching HeatWave / MySQL, start the bundled mock backend:

```bash
.venv/bin/python tests/ui_support/mock_backend_server.py 8766 BluebonnetLonghorn.png
```

Then point Streamlit at it:

```bash
HEATWAVE_API_BASE_URL=http://127.0.0.1:8766 .venv/bin/streamlit run heatwave_image_app.py
```

## Backend API

The FastAPI service exposes:

- `GET /health`
- `GET /app-info`
- `GET /images?search=...`
- `GET /images/{id}`
- `GET /images/{id}/content`
- `POST /images`
- `POST /descriptions/generate-upload`
- `PUT /images/{id}/description`
- `POST /images/{id}/description/generate`
- `POST /images/{id}/insights`

## What the backend creates

At startup, the app ensures that the target schema and table exist. By default, it uses:

- schema: `image_registry`
- table: `image_assets`

Each stored image record includes the image name, original filename, MIME type, base64 payload, a reusable description, and timestamps.

At startup, the backend reads the ordered SQL files in `sql/` and applies them with `CREATE ... IF NOT EXISTS`, so a fresh HeatWave instance is initialized automatically and an existing one is skipped safely.

## Testing

Run the Python test suite with:

```bash
.venv/bin/python -m pytest tests
```

For quick syntax verification:

```bash
.venv/bin/python -m py_compile heatwave_image_app.py backend/*.py
```

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
