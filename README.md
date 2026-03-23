# HeatWave Image Intelligence

Streamlit app for storing image payloads in Oracle HeatWave, browsing the library, and asking HeatWave to describe or analyze a selected image.

## What is in this repo

- `heatwave_image_app.py` - main Streamlit app
- `img_to_base64.py` - helper to convert an image file into a base64 text file
- `A-Class_Plate_NA.png.webp` and `Screenshot 2026-02-17 at 4.38.13 p.m..png` - sample assets

## Requirements

- Python 3.9 or newer
- Network access to the HeatWave/MySQL host
- `pip` access to install Python packages
- A database user that can create and read the `image_registry.image_assets` table

The app defaults to the current HeatWave connection used by the script, but you can override it with environment variables:

- `DB_HOST`
- `DB_PORT`
- `DB_USER`
- `DB_PASSWORD`
- `DB_NAME` or `DB_SCHEMA`
- `AI_MODEL_ID`
- `AI_LANGUAGE`

## Local run

From the repository root:

```bash
python3.9 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python heatwave_image_app.py
```

`heatwave_image_app.py` will bootstrap Streamlit if needed and then launch the app.

If you already have the dependencies installed in the current interpreter, you can also run:

```bash
streamlit run heatwave_image_app.py
```

## VM run

On the Oracle Linux / RHEL 8 VM used for deployment, the system Python is 3.6 and is too old for modern Streamlit. Install Python 3.9 first, then run the same project commands:

```bash
sudo dnf install -y python39 python39-pip
python3.9 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python heatwave_image_app.py
```

## Helper script

`img_to_base64.py` converts an image to a base64 text file and can optionally include a `data:` URL prefix.

Example:

```bash
python img_to_base64.py A-Class_Plate_NA.png.webp
```

## Notes

- The app creates the `image_registry.image_assets` table if it does not already exist.
- The AI response feature uses `sys.ML_GENERATE` and the selected image payload.
- If the database credentials or HeatWave endpoint change, set the environment variables above before launching the app.
