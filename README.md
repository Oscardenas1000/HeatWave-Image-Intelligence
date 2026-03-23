# HeatWave Image Intelligence

HeatWave Image Intelligence is a Streamlit app for:

- uploading images into Oracle HeatWave as base64 payloads
- browsing a searchable image library
- asking HeatWave AI to describe or analyze a selected image with `sys.ML_GENERATE`

## Project layout

- `heatwave_image_app.py`: main Streamlit application
- `img_to_base64.py`: helper that converts an image file into a base64 text file
- `requirements.txt`: Python dependencies
- `.env.example`: required runtime configuration template
- `scripts/deploy_to_vm.sh`: repeatable Linux VM deployment helper
- `deploy/systemd/heatwave-image-intelligence.service`: optional systemd unit for long-running VM hosting

## Prerequisites

- Python 3.9+
- network access to your HeatWave / MySQL instance
- a database user that can create and read the target schema and table
- HeatWave `ML_GENERATE` access for image-aware prompts

## Quick start

1. Create a virtual environment and install dependencies.

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

4. Launch the app.

```bash
.venv/bin/python heatwave_image_app.py
```

The script will hand off to Streamlit automatically. You can also run it directly with:

```bash
.venv/bin/streamlit run heatwave_image_app.py
```

## What the app creates

At startup, the app ensures that the target schema and table exist. By default, it uses:

- schema: `image_registry`
- table: `image_assets`

Each stored image record includes the image name, original filename, MIME type, base64 payload, and timestamps.

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
