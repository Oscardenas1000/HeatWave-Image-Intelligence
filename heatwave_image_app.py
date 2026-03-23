#!/usr/bin/env python3
import base64
import binascii
import importlib.util
import json
import mimetypes
import os
import subprocess
import sys
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Optional

APP_PATH = Path(__file__).resolve()
APP_DIR = APP_PATH.parent
VENV_DIR = APP_DIR / ".venv"
REQUIRED_PACKAGES = ("streamlit", "mysql-connector-python", "pillow")

DB_HOST = os.getenv("DB_HOST", "163.192.105.216")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "admin")
DB_PASSWORD = os.getenv("DB_PASSWORD", "@Mysqlse2025")
DB_SCHEMA = os.getenv("DB_NAME", os.getenv("DB_SCHEMA", "image_registry"))
DB_TABLE = "image_assets"
AI_MODEL_ID = os.getenv("AI_MODEL_ID", "google.gemini-2.5-pro")
AI_LANGUAGE = os.getenv("AI_LANGUAGE", "en")
IMAGE_UPLOAD_TYPES = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]

_STREAMLIT = None
_MYSQL_CONNECTOR = None
_PIL_IMAGE = None


@dataclass
class ImagePayload:
    image_name: str
    original_filename: str
    mime_type: str
    base64_payload: str


def module_available(module_name: str) -> bool:
    try:
        return importlib.util.find_spec(module_name) is not None
    except ModuleNotFoundError:
        return False


def in_streamlit_runtime() -> bool:
    try:
        from streamlit.runtime.scriptrunner import get_script_run_ctx  # type: ignore

        return get_script_run_ctx() is not None
    except Exception:
        return False


def ensure_runtime_dependencies() -> None:
    python_bin = VENV_DIR / "bin" / "python"
    pip_bin = VENV_DIR / "bin" / "pip"
    missing = []

    if not module_available("streamlit"):
        missing.append("streamlit")

    if not module_available("mysql.connector"):
        missing.append("mysql-connector-python")

    if not module_available("PIL"):
        missing.append("pillow")

    if not missing:
        return

    if in_streamlit_runtime():
        raise RuntimeError(
            "Missing dependencies in the current Streamlit interpreter. "
            "Run `python heatwave_image_app.py` once to bootstrap the local runtime."
        )

    if python_bin.exists():
        ready = subprocess.run(
            [str(python_bin), "-c", "import streamlit, mysql.connector, PIL"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if ready.returncode == 0:
            os.execv(str(python_bin), [str(python_bin), str(APP_PATH), *sys.argv[1:]])

    if not python_bin.exists():
        subprocess.check_call([sys.executable, "-m", "venv", str(VENV_DIR)])

    subprocess.check_call([str(pip_bin), "install", *REQUIRED_PACKAGES])
    os.execv(str(python_bin), [str(python_bin), str(APP_PATH), *sys.argv[1:]])


def get_streamlit():
    global _STREAMLIT
    if _STREAMLIT is None:
        import streamlit as st  # type: ignore

        _STREAMLIT = st
    return _STREAMLIT


def get_mysql_connector():
    global _MYSQL_CONNECTOR
    if _MYSQL_CONNECTOR is None:
        import mysql.connector  # type: ignore

        _MYSQL_CONNECTOR = mysql.connector
    return _MYSQL_CONNECTOR


def get_pil_image():
    global _PIL_IMAGE
    if _PIL_IMAGE is None:
        from PIL import Image  # type: ignore

        _PIL_IMAGE = Image
    return _PIL_IMAGE


def get_connection(database: Optional[str] = DB_SCHEMA):
    mysql_connector = get_mysql_connector()
    kwargs = {
        "host": DB_HOST,
        "port": DB_PORT,
        "user": DB_USER,
        "password": DB_PASSWORD,
        "autocommit": True,
    }
    if database is not None:
        kwargs["database"] = database
    return mysql_connector.connect(**kwargs)


def execute_sql(
    sql: str,
    params: tuple = (),
    *,
    fetch: bool = False,
    database: Optional[str] = DB_SCHEMA,
):
    conn = get_connection(database=database)
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params)
        if fetch:
            return cursor.fetchall()
        return None
    finally:
        conn.close()


def ensure_schema_and_table() -> None:
    execute_sql(
        """
        CREATE SCHEMA IF NOT EXISTS image_registry
        DEFAULT CHARACTER SET utf8mb4
        COLLATE utf8mb4_0900_ai_ci
        """,
        database=None,
    )
    execute_sql(
        """
        CREATE TABLE IF NOT EXISTS image_registry.image_assets (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            image_name VARCHAR(255) NOT NULL,
            original_filename VARCHAR(255) NOT NULL,
            mime_type VARCHAR(100) NOT NULL,
            base64_payload LONGTEXT NOT NULL,
            created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
            PRIMARY KEY (id),
            KEY idx_image_assets_name_created_at (image_name, created_at, id),
            KEY idx_image_assets_created_at (created_at, id)
        ) ENGINE=InnoDB
        DEFAULT CHARSET=utf8mb4
        COLLATE=utf8mb4_0900_ai_ci
        COMMENT='Base64 image registry for manual upload and review'
        """
    )


def clean_base64_text(base64_text: str) -> tuple[str, Optional[str]]:
    text = "".join(base64_text.split())
    mime_hint = None

    if text.startswith("data:"):
        header, separator, payload = text.partition(",")
        if not separator or not payload:
            raise ValueError("The data URL is incomplete.")
        if ";base64" not in header:
            raise ValueError("Only base64 data URLs are supported.")
        mime_hint = header[5:].split(";", 1)[0] or None
        text = payload

    return text, mime_hint


def decode_base64_text(base64_text: str) -> tuple[bytes, str, Optional[str]]:
    cleaned, mime_hint = clean_base64_text(base64_text)
    try:
        decoded = base64.b64decode(cleaned, validate=True)
    except binascii.Error as exc:
        raise ValueError(f"Base64 payload is invalid: {exc}") from exc
    return decoded, cleaned, mime_hint


def detect_image_details(image_bytes: bytes) -> dict:
    Image = get_pil_image()
    with Image.open(BytesIO(image_bytes)) as img:
        return {
            "format": img.format,
            "width": img.width,
            "height": img.height,
        }


def build_payload_from_upload(uploaded_file, image_name: str) -> tuple[ImagePayload, bytes, dict]:
    image_bytes = uploaded_file.getvalue()
    mime_type = uploaded_file.type or mimetypes.guess_type(uploaded_file.name)[0]
    mime_type = mime_type or "application/octet-stream"
    payload = ImagePayload(
        image_name=image_name.strip(),
        original_filename=uploaded_file.name or "uploaded-image",
        mime_type=mime_type,
        base64_payload=base64.b64encode(image_bytes).decode("ascii"),
    )
    return payload, image_bytes, detect_image_details(image_bytes)


def inject_styles(st) -> None:
    st.markdown(
        """
        <style>
        .stApp {
            background:
                radial-gradient(circle at top left, rgba(195, 229, 255, 0.65), transparent 34%),
                radial-gradient(circle at top right, rgba(255, 228, 212, 0.5), transparent 28%),
                linear-gradient(180deg, #f7f8fb 0%, #eff2f7 100%);
            color: #1d1d1f;
        }
        .block-container {
            max-width: 1180px;
            padding-top: 2.25rem;
            padding-bottom: 3rem;
        }
        h1, h2, h3, p, div, span, label {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif;
        }
        h1, h2, h3 {
            color: #1d1d1f;
            letter-spacing: -0.03em;
        }
        div[data-testid="stVerticalBlockBorderWrapper"] {
            border-radius: 26px;
            border: 1px solid rgba(17, 17, 17, 0.06);
            background: rgba(255, 255, 255, 0.72);
            box-shadow: 0 18px 54px rgba(15, 23, 42, 0.07);
            backdrop-filter: blur(18px);
        }
        div[data-testid="stTextInputRootElement"] input,
        div[data-testid="stTextArea"] textarea,
        div[data-testid="stFileUploader"] section,
        div[data-baseweb="select"] > div {
            border-radius: 18px !important;
            border: 1px solid rgba(17, 17, 17, 0.08) !important;
            background: rgba(255, 255, 255, 0.92) !important;
        }
        .stButton > button {
            border-radius: 999px;
            border: none;
            background: linear-gradient(180deg, #1c7ef6 0%, #0a62d0 100%);
            color: white;
            font-weight: 600;
            min-height: 3rem;
            padding: 0.85rem 1.25rem;
            box-shadow: 0 10px 24px rgba(10, 98, 208, 0.22);
        }
        .stButton > button:disabled {
            background: #d7dbe3;
            box-shadow: none;
            color: #7a7f87;
        }
        div[data-testid="stImage"] img {
            border-radius: 24px;
        }
        .app-hero {
            padding: 0.4rem 0 1.4rem 0;
        }
        .app-eyebrow {
            margin: 0 0 0.8rem 0;
            font-size: 0.72rem;
            text-transform: uppercase;
            letter-spacing: 0.18em;
            color: #6e6e73;
        }
        .app-hero h1 {
            margin: 0;
            font-size: clamp(2.7rem, 5vw, 4.8rem);
            line-height: 0.96;
            font-weight: 650;
        }
        .app-hero p {
            margin: 0.9rem 0 0 0;
            max-width: 700px;
            font-size: 1.08rem;
            line-height: 1.6;
            color: #4f535c;
        }
        .app-pills {
            display: flex;
            gap: 0.65rem;
            flex-wrap: wrap;
            margin-top: 1.2rem;
        }
        .app-pill {
            display: inline-flex;
            align-items: center;
            padding: 0.48rem 0.82rem;
            border-radius: 999px;
            background: rgba(255, 255, 255, 0.78);
            border: 1px solid rgba(17, 17, 17, 0.05);
            color: #3b414b;
            font-size: 0.92rem;
        }
        .section-intro {
            padding-bottom: 0.5rem;
        }
        .section-intro h2 {
            margin: 0;
            font-size: 1.6rem;
            font-weight: 600;
        }
        .section-intro p {
            margin: 0.45rem 0 0 0;
            color: #5f636b;
            line-height: 1.55;
        }
        .section-eyebrow {
            margin: 0 0 0.45rem 0;
            font-size: 0.76rem;
            letter-spacing: 0.14em;
            text-transform: uppercase;
            color: #7b8088;
        }
        .quiet-empty {
            padding: 2rem 1.3rem;
            border-radius: 22px;
            border: 1px dashed rgba(17, 17, 17, 0.12);
            background: rgba(255, 255, 255, 0.5);
            text-align: center;
        }
        .quiet-empty strong {
            display: block;
            font-size: 1.02rem;
            color: #1d1d1f;
            margin-bottom: 0.35rem;
        }
        .quiet-empty span {
            color: #6a6f78;
            line-height: 1.55;
        }
        .subtle-copy {
            color: #6a6f78;
            font-size: 0.92rem;
            line-height: 1.55;
        }
        </style>
        """,
        unsafe_allow_html=True,
    )


def render_section_intro(st, eyebrow: str, title: str, copy: str) -> None:
    st.markdown(
        f"""
        <div class="section-intro">
            <p class="section-eyebrow">{eyebrow}</p>
            <h2>{title}</h2>
            <p>{copy}</p>
        </div>
        """,
        unsafe_allow_html=True,
    )


def render_empty_state(st, title: str, copy: str) -> None:
    st.markdown(
        f"""
        <div class="quiet-empty">
            <strong>{title}</strong>
            <span>{copy}</span>
        </div>
        """,
        unsafe_allow_html=True,
    )


def format_record_label(row: dict) -> str:
    return f"{row['image_name']} · #{row['id']}"


def insert_payload(payload: ImagePayload) -> None:
    execute_sql(
        """
        INSERT INTO image_registry.image_assets (
            image_name,
            original_filename,
            mime_type,
            base64_payload
        )
        VALUES (%s, %s, %s, %s)
        """,
        (
            payload.image_name,
            payload.original_filename,
            payload.mime_type,
            payload.base64_payload,
        ),
    )


def parse_ml_generate_response(raw_response) -> str:
    if raw_response is None:
        return ""

    if isinstance(raw_response, (bytes, bytearray)):
        raw_response = raw_response.decode("utf-8", errors="replace")

    response_text = str(raw_response)
    try:
        parsed = json.loads(response_text)
    except json.JSONDecodeError:
        return response_text.strip()

    if isinstance(parsed, dict) and isinstance(parsed.get("text"), str):
        return parsed["text"].strip()
    return response_text.strip()


def generate_image_insight(record_id: int, prompt: str) -> str:
    cleaned_prompt = prompt.strip()
    if not cleaned_prompt:
        raise ValueError("Enter a prompt before generating an AI response.")

    conn = get_connection(database=DB_SCHEMA)
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SET @image_base64 = NULL")
        cursor.execute(
            """
            SELECT base64_payload
            INTO @image_base64
            FROM image_registry.image_assets
            WHERE id = %s
            """,
            (record_id,),
        )
        cursor.execute("SELECT CHAR_LENGTH(@image_base64) AS payload_length")
        payload_row = cursor.fetchone()
        if not payload_row or not payload_row.get("payload_length"):
            raise RuntimeError("The selected image record is no longer available.")
        cursor.execute(
            """
            SELECT sys.ML_GENERATE(
                %s,
                JSON_OBJECT(
                    'language', %s,
                    'model_id', %s,
                    'image', @image_base64
                )
            ) AS response
            """,
            (cleaned_prompt, AI_LANGUAGE, AI_MODEL_ID),
        )
        row = cursor.fetchone()
        if not row:
            raise RuntimeError("HeatWave did not return a response.")
        return parse_ml_generate_response(row.get("response"))
    finally:
        conn.close()


def fetch_records(name_filter: str = ""):
    if name_filter.strip():
        return execute_sql(
            """
            SELECT
                id,
                image_name,
                original_filename,
                mime_type,
                CHAR_LENGTH(base64_payload) AS base64_length,
                created_at,
                updated_at
            FROM image_registry.image_assets
            WHERE image_name LIKE %s
            ORDER BY created_at DESC, id DESC
            """,
            (f"%{name_filter.strip()}%",),
            fetch=True,
        )

    return execute_sql(
        """
        SELECT
            id,
            image_name,
            original_filename,
            mime_type,
            CHAR_LENGTH(base64_payload) AS base64_length,
            created_at,
            updated_at
        FROM image_registry.image_assets
        ORDER BY created_at DESC, id DESC
        """,
        fetch=True,
    )


def fetch_record(record_id: int):
    rows = execute_sql(
        """
        SELECT
            id,
            image_name,
            original_filename,
            mime_type,
            base64_payload,
            created_at,
            updated_at
        FROM image_registry.image_assets
        WHERE id = %s
        """,
        (record_id,),
        fetch=True,
    )
    return rows[0] if rows else None


def render_image_details(st, image_details: dict, payload: ImagePayload) -> None:
    st.caption(
        f"{image_details['format']} | {image_details['width']}x{image_details['height']} | "
        f"{payload.mime_type} | {len(payload.base64_payload):,} base64 chars"
    )


def show_review_panel(st, record: dict) -> None:
    image_bytes, cleaned_base64, _ = decode_base64_text(record["base64_payload"])
    image_details = detect_image_details(image_bytes)
    image_col, detail_col = st.columns([1.12, 0.88], gap="large")

    with image_col:
        st.image(image_bytes, caption=record["image_name"], use_container_width=True)
        st.caption(
            f"{image_details['format']} | {image_details['width']}x{image_details['height']} | "
            f"{len(cleaned_base64):,} base64 chars"
        )

    with detail_col:
        st.markdown(f"### {record['image_name']}")
        meta_top, meta_bottom = st.columns(2)

        with meta_top:
            st.caption("Original file")
            st.write(record["original_filename"])
            st.caption("Created")
            st.write(str(record["created_at"]))

        with meta_bottom:
            st.caption("MIME type")
            st.write(record["mime_type"])
            st.caption("Updated")
            st.write(str(record["updated_at"]))


def show_ai_insight_panel(st, record: dict) -> None:
    prompt_key = f"ai_prompt_{record['id']}"
    response_key = f"ai_response_{record['id']}"
    default_prompt = "Describe this image and call out the most important visible details."

    render_section_intro(
        st,
        "AI Insight",
        "Ask about the selected image",
        f"The response is generated by HeatWave with `{AI_MODEL_ID}` using the image shown on this page.",
    )

    prompt = st.text_area(
        "Ask a question about this image",
        key=prompt_key,
        height=120,
        placeholder=default_prompt,
    )

    if st.button(
        "Generate insight",
        key=f"generate_ai_response_{record['id']}",
        type="primary",
        use_container_width=True,
        disabled=not prompt.strip(),
    ):
        try:
            with st.spinner("Generating response from HeatWave..."):
                st.session_state[response_key] = generate_image_insight(record["id"], prompt)
        except Exception as exc:
            st.session_state.pop(response_key, None)
            st.error(f"AI generation failed: {exc}")

    if response_key in st.session_state:
        with st.container(border=True):
            st.write(st.session_state[response_key])
    else:
        st.markdown(
            '<p class="subtle-copy">Enter a question to generate a grounded response for the selected image.</p>',
            unsafe_allow_html=True,
        )


def run_streamlit_app() -> None:
    st = get_streamlit()
    st.set_page_config(
        page_title="Image Library",
        layout="wide",
        initial_sidebar_state="collapsed",
    )

    ensure_schema_and_table()
    inject_styles(st)

    all_records = fetch_records()
    note = st.session_state.pop("app_note", "")

    st.markdown(
        f"""
        <div class="app-hero">
            <p class="app-eyebrow">Image Intelligence</p>
            <h1>Upload once. Review clearly. Ask naturally.</h1>
            <p>
                A quieter interface for storing image payloads in HeatWave, browsing your library,
                and generating AI insights without dashboard clutter.
            </p>
            <div class="app-pills">
                <span class="app-pill">{len(all_records)} image record(s)</span>
                <span class="app-pill">{AI_MODEL_ID}</span>
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )
    if note:
        st.caption(note)

    with st.container(border=True):
        render_section_intro(
            st,
            "Create",
            "Upload an image",
            "The app generates the base64 payload automatically and saves it in HeatWave with the manual name you choose.",
        )
        form_col, preview_col = st.columns([0.92, 1.08], gap="large")

        uploaded_file = None
        upload_name = ""

        with form_col:
            upload_name = st.text_input(
                "Image name",
                key="upload_image_name",
                placeholder="Example: Front bumper close-up",
            )
            uploaded_file = st.file_uploader(
                "Choose an image",
                type=IMAGE_UPLOAD_TYPES,
                key="uploaded_image_file",
            )
            st.markdown(
                '<p class="subtle-copy">Supported formats: PNG, JPG, WEBP, GIF, and BMP.</p>',
                unsafe_allow_html=True,
            )

            save_disabled = uploaded_file is None or not upload_name.strip()
            if st.button(
                "Save to library",
                key="save_uploaded_image",
                type="primary",
                use_container_width=True,
                disabled=save_disabled,
            ):
                try:
                    payload, _, _ = build_payload_from_upload(uploaded_file, upload_name)
                    insert_payload(payload)
                    st.session_state["app_note"] = f'Added "{payload.image_name}" to the library.'
                    st.rerun()
                except Exception as exc:
                    st.error(f"Unable to prepare the uploaded image: {exc}")

        with preview_col:
            if uploaded_file is not None:
                try:
                    preview_bytes = uploaded_file.getvalue()
                    preview_details = detect_image_details(preview_bytes)
                    preview_name = upload_name.strip() or uploaded_file.name
                    preview_payload = ImagePayload(
                        image_name=preview_name,
                        original_filename=uploaded_file.name or "uploaded-image",
                        mime_type=uploaded_file.type
                        or mimetypes.guess_type(uploaded_file.name)[0]
                        or "application/octet-stream",
                        base64_payload=base64.b64encode(preview_bytes).decode("ascii"),
                    )
                    st.image(preview_bytes, caption=preview_name, use_container_width=True)
                    render_image_details(st, preview_details, preview_payload)
                except Exception as exc:
                    st.error(f"Unable to preview the selected image: {exc}")
            else:
                render_empty_state(
                    st,
                    "Preview appears here",
                    "Choose an image and give it a name to prepare it for your library.",
                )

    with st.container(border=True):
        render_section_intro(
            st,
            "Library",
            "Review saved images",
            "Search by name, choose a record, and ask AI questions while keeping the image visible.",
        )

        records_filter_col, records_select_col = st.columns([0.62, 1.38], gap="large")
        with records_filter_col:
            name_filter = st.text_input(
                "Search library",
                key="record_name_filter",
                placeholder="Find an image by name",
            )

        filtered_records = fetch_records(name_filter)

        if filtered_records:
            record_lookup = {row["id"]: row for row in filtered_records}
            record_ids = list(record_lookup.keys())
            current_record_id = st.session_state.get("selected_record_id", record_ids[0])
            if current_record_id not in record_lookup:
                current_record_id = record_ids[0]

            with records_select_col:
                selected_record_id = st.selectbox(
                    "Image library",
                    options=record_ids,
                    index=record_ids.index(current_record_id),
                    format_func=lambda record_id: format_record_label(record_lookup[record_id]),
                    key="selected_record_id",
                )

            record = fetch_record(selected_record_id)
            if record:
                try:
                    show_review_panel(st, record)
                    show_ai_insight_panel(st, record)
                except Exception as exc:
                    st.error(f"Unable to render the stored image: {exc}")
        else:
            render_empty_state(
                st,
                "No images to review",
                "Upload an image to start a library, or adjust the search field to bring records back into view.",
            )


def run_as_python() -> None:
    python_bin = sys.executable
    try:
        raise SystemExit(
            subprocess.call([python_bin, "-m", "streamlit", "run", str(APP_PATH)])
        )
    except KeyboardInterrupt:
        raise SystemExit(0)


def main() -> None:
    ensure_runtime_dependencies()
    if in_streamlit_runtime():
        run_streamlit_app()
    else:
        run_as_python()


if __name__ == "__main__":
    main()
