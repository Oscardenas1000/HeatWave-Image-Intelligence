#!/usr/bin/env python3
from __future__ import annotations

import html
import importlib.util
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any, Mapping, Optional
from urllib.parse import urlparse

APP_PATH = Path(__file__).resolve()
APP_DIR = APP_PATH.parent
ENV_PATH = APP_DIR / ".env"
VENV_DIR = APP_DIR / ".venv"
SETTINGS_PATH = Path.home() / ".heatwave-image-intelligence" / "streamlit-settings.json"

REQUIRED_PACKAGES = ("streamlit", "httpx", "pillow")
DEFAULT_BACKEND_URL = "http://127.0.0.1:8000"
DEFAULT_INSIGHT_PROMPT = "Describe this image and call out the most important visible details."
DEFAULT_LAUNCH_SOURCE = "direct-streamlit-run"
DEFAULT_SEARCH_PLACEHOLDER = "Find an image by name"
UPLOAD_DESCRIPTION_PROMPT_PLACEHOLDER = (
    "Optional guidance for auto-generating the image description."
)
DETAIL_DESCRIPTION_PROMPT_PLACEHOLDER = (
    "Optional guidance for regenerating the description."
)
UPLOAD_DESCRIPTION_PLACEHOLDER = (
    "Enter a manual description or generate one from the image."
)
DETAIL_DESCRIPTION_PLACEHOLDER = "Write a description manually or generate one from the image."

BASE_URL_ENV_KEY = "HEATWAVE_API_BASE_URL"
RUN_STAMP_ENV_KEY = "HEATWAVE_BUILD_STAMP"
LAUNCH_SOURCE_ENV_KEY = "HEATWAVE_LAUNCH_SOURCE"
PROMPT_LOG_PATH_ENV_KEY = "HEATWAVE_PROMPT_LOG_PATH"

IMAGE_UPLOAD_TYPES = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
BACKEND_ERROR_SHAPE = "The backend returned an invalid response."
BACKEND_URL_VALIDATION_MESSAGE = (
    "Enter a valid backend URL including the scheme and host."
)

_STREAMLIT = None
_HTTPX = None
_PIL_IMAGE = None

LANGUAGE_DISPLAY_NAMES = {
    "ar": "Arabic",
    "cs": "Czech",
    "da": "Danish",
    "de": "German",
    "el": "Greek",
    "en": "English",
    "es": "Spanish",
    "fi": "Finnish",
    "fr": "French",
    "he": "Hebrew",
    "hi": "Hindi",
    "hu": "Hungarian",
    "it": "Italian",
    "ja": "Japanese",
    "ko": "Korean",
    "nl": "Dutch",
    "no": "Norwegian",
    "pl": "Polish",
    "pt": "Portuguese",
    "ro": "Romanian",
    "ru": "Russian",
    "sv": "Swedish",
    "th": "Thai",
    "tr": "Turkish",
    "uk": "Ukrainian",
    "vi": "Vietnamese",
    "zh": "Chinese",
}


@dataclass(frozen=True)
class RuntimeDiagnostics:
    base_url: str
    run_stamp: str
    launch_source: str
    prompt_log_path: Optional[str]


@dataclass(frozen=True)
class AppInfo:
    ai_model_id: str
    record_count: int


@dataclass(frozen=True)
class ImageSummary:
    id: int
    image_name: str
    original_filename: str
    mime_type: str
    base64_length: int
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class ImageDetail:
    id: int
    image_name: str
    original_filename: str
    mime_type: str
    description: Optional[str]
    base64_length: int
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class GeneratedDescriptionResponse:
    description: str
    detected_language: Optional[str]


@dataclass(frozen=True)
class InsightResponse:
    text: str
    detected_language: Optional[str]


@dataclass(frozen=True)
class ImagePreviewDetails:
    format_name: str
    width: int
    height: int


class BackendClientError(RuntimeError):
    pass


def load_dotenv_file(dotenv_path: Path = ENV_PATH) -> None:
    if not dotenv_path.exists():
        return

    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def trimmed_non_empty(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    trimmed = value.strip()
    return trimmed or None


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

    if not module_available("httpx"):
        missing.append("httpx")

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
            [str(python_bin), "-c", "import streamlit, httpx, PIL"],
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


def get_httpx():
    global _HTTPX
    if _HTTPX is None:
        import httpx  # type: ignore

        _HTTPX = httpx
    return _HTTPX


def get_pil_image():
    global _PIL_IMAGE
    if _PIL_IMAGE is None:
        from PIL import Image  # type: ignore

        _PIL_IMAGE = Image
    return _PIL_IMAGE


def make_fallback_run_stamp(now: Optional[datetime] = None) -> str:
    resolved_now = now or datetime.now(timezone.utc)
    if resolved_now.tzinfo is None:
        resolved_now = resolved_now.replace(tzinfo=timezone.utc)
    else:
        resolved_now = resolved_now.astimezone(timezone.utc)

    return f"direct-{resolved_now.strftime('%Y-%m-%dT%H%M%SZ')}"


def load_persisted_base_url(settings_path: Path = SETTINGS_PATH) -> Optional[str]:
    try:
        payload = json.loads(settings_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return None

    if not isinstance(payload, dict):
        return None

    return trimmed_non_empty(payload.get("base_url"))


def save_persisted_base_url(base_url: str, settings_path: Path = SETTINGS_PATH) -> None:
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    settings_path.write_text(
        json.dumps({"base_url": base_url}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def default_base_url_from_environment(
    environment: Optional[Mapping[str, str]] = None,
) -> str:
    environment = environment or os.environ
    return trimmed_non_empty(environment.get(BASE_URL_ENV_KEY)) or DEFAULT_BACKEND_URL


def build_runtime_diagnostics(
    environment: Mapping[str, str],
    persisted_base_url: Optional[str],
    *,
    now: Optional[datetime] = None,
) -> RuntimeDiagnostics:
    base_url = (
        trimmed_non_empty(environment.get(BASE_URL_ENV_KEY))
        or persisted_base_url
        or DEFAULT_BACKEND_URL
    )
    run_stamp = (
        trimmed_non_empty(environment.get(RUN_STAMP_ENV_KEY))
        or make_fallback_run_stamp(now=now)
    )
    launch_source = (
        trimmed_non_empty(environment.get(LAUNCH_SOURCE_ENV_KEY))
        or DEFAULT_LAUNCH_SOURCE
    )
    prompt_log_path = trimmed_non_empty(environment.get(PROMPT_LOG_PATH_ENV_KEY))

    return RuntimeDiagnostics(
        base_url=base_url,
        run_stamp=run_stamp,
        launch_source=launch_source,
        prompt_log_path=prompt_log_path,
    )


def validate_base_url(base_url: str) -> Optional[str]:
    trimmed = base_url.strip()
    if not trimmed:
        return BACKEND_URL_VALIDATION_MESSAGE

    parsed = urlparse(trimmed)
    if not parsed.scheme or not parsed.hostname:
        return BACKEND_URL_VALIDATION_MESSAGE

    return None


def invalid_backend_url_message(base_url: str) -> str:
    return f"Invalid backend URL: {base_url}"


def parse_datetime(value: Any) -> datetime:
    text_value = str(value).strip()
    if text_value.endswith("Z"):
        text_value = text_value[:-1] + "+00:00"
    return datetime.fromisoformat(text_value)


def parse_app_info(payload: Mapping[str, Any]) -> AppInfo:
    return AppInfo(
        ai_model_id=str(payload.get("aiModelId", "")),
        record_count=int(payload.get("recordCount", 0)),
    )


def parse_image_summary(payload: Mapping[str, Any]) -> ImageSummary:
    return ImageSummary(
        id=int(payload["id"]),
        image_name=str(payload["imageName"]),
        original_filename=str(payload["originalFilename"]),
        mime_type=str(payload["mimeType"]),
        base64_length=int(payload["base64Length"]),
        created_at=parse_datetime(payload["createdAt"]),
        updated_at=parse_datetime(payload["updatedAt"]),
    )


def parse_image_detail(payload: Mapping[str, Any]) -> ImageDetail:
    return ImageDetail(
        id=int(payload["id"]),
        image_name=str(payload["imageName"]),
        original_filename=str(payload["originalFilename"]),
        mime_type=str(payload["mimeType"]),
        description=trimmed_non_empty(payload.get("description")),
        base64_length=int(payload["base64Length"]),
        created_at=parse_datetime(payload["createdAt"]),
        updated_at=parse_datetime(payload["updatedAt"]),
    )


def parse_generated_description(payload: Mapping[str, Any]) -> GeneratedDescriptionResponse:
    return GeneratedDescriptionResponse(
        description=str(payload.get("description", "")),
        detected_language=trimmed_non_empty(payload.get("detectedLanguage")),
    )


def parse_insight_response(payload: Mapping[str, Any]) -> InsightResponse:
    return InsightResponse(
        text=str(payload.get("text", "")),
        detected_language=trimmed_non_empty(payload.get("detectedLanguage")),
    )


def decode_error_message(response: Any) -> str:
    try:
        payload = response.json()
    except Exception:
        payload = None

    if isinstance(payload, dict):
        error_message = trimmed_non_empty(payload.get("error"))
        if error_message:
            return error_message

    raw_text = trimmed_non_empty(getattr(response, "text", None))
    if raw_text:
        return raw_text

    return f"Backend request failed with status {response.status_code}."


class BackendClient:
    def __init__(self, base_url: str) -> None:
        validation_message = validate_base_url(base_url)
        if validation_message is not None:
            raise BackendClientError(invalid_backend_url_message(base_url))
        self.base_url = base_url.strip().rstrip("/")

    def _url(self, path: str) -> str:
        return f"{self.base_url}/{path.lstrip('/')}"

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: Optional[Mapping[str, Any]] = None,
        data: Optional[Mapping[str, Any]] = None,
        files: Optional[Mapping[str, Any]] = None,
        json_payload: Optional[Mapping[str, Any]] = None,
    ):
        httpx = get_httpx()
        try:
            with httpx.Client(timeout=30.0, follow_redirects=True) as client:
                response = client.request(
                    method,
                    self._url(path),
                    params=params,
                    data=data,
                    files=files,
                    json=json_payload,
                    headers={"Accept": "application/json"},
                )
        except httpx.HTTPError as exc:  # type: ignore[attr-defined]
            raise BackendClientError(
                f"Unable to reach the backend at {self.base_url}: {exc}"
            ) from exc

        if not response.is_success:
            raise BackendClientError(decode_error_message(response))

        return response

    def _json(self, response) -> Any:
        try:
            return response.json()
        except ValueError as exc:
            raise BackendClientError(BACKEND_ERROR_SHAPE) from exc

    def fetch_app_info(self) -> AppInfo:
        response = self._request("GET", "/app-info")
        return parse_app_info(self._json(response))

    def fetch_images(self, search: str) -> list[ImageSummary]:
        params = {"search": search} if search else None
        response = self._request("GET", "/images", params=params)
        payload = self._json(response)
        return [parse_image_summary(item) for item in payload]

    def fetch_image(self, record_id: int) -> ImageDetail:
        response = self._request("GET", f"/images/{record_id}")
        return parse_image_detail(self._json(response))

    def fetch_image_content(self, record_id: int) -> bytes:
        response = self._request("GET", f"/images/{record_id}/content")
        return bytes(response.content)

    def upload_image(
        self,
        *,
        image_name: str,
        filename: str,
        mime_type: Optional[str],
        image_bytes: bytes,
        description: str,
    ) -> ImageDetail:
        response = self._request(
            "POST",
            "/images",
            data={
                "image_name": image_name,
                "description": description,
            },
            files={
                "file": (
                    filename,
                    image_bytes,
                    mime_type or "application/octet-stream",
                )
            },
        )
        return parse_image_detail(self._json(response))

    def generate_upload_description(
        self,
        *,
        filename: str,
        mime_type: Optional[str],
        image_bytes: bytes,
        prompt: str,
    ) -> GeneratedDescriptionResponse:
        response = self._request(
            "POST",
            "/descriptions/generate-upload",
            data={"prompt": prompt},
            files={
                "file": (
                    filename,
                    image_bytes,
                    mime_type or "application/octet-stream",
                )
            },
        )
        return parse_generated_description(self._json(response))

    def update_image_description(
        self,
        *,
        record_id: int,
        description: str,
    ) -> ImageDetail:
        response = self._request(
            "PUT",
            f"/images/{record_id}/description",
            json_payload={"description": description},
        )
        return parse_image_detail(self._json(response))

    def generate_image_description(
        self,
        *,
        record_id: int,
        prompt: str,
    ) -> ImageDetail:
        response = self._request(
            "POST",
            f"/images/{record_id}/description/generate",
            json_payload={"prompt": prompt},
        )
        return parse_image_detail(self._json(response))

    def generate_insight(
        self,
        *,
        record_id: int,
        prompt: str,
    ) -> InsightResponse:
        response = self._request(
            "POST",
            f"/images/{record_id}/insights",
            json_payload={"prompt": prompt},
        )
        return parse_insight_response(self._json(response))


def detect_image_details(image_bytes: bytes) -> ImagePreviewDetails:
    Image = get_pil_image()
    with Image.open(BytesIO(image_bytes)) as image:
        image.load()
        return ImagePreviewDetails(
            format_name=(image.format or "Image").upper(),
            width=image.width,
            height=image.height,
        )


def format_timestamp(value: datetime) -> str:
    resolved_value = value
    if resolved_value.tzinfo is not None:
        resolved_value = resolved_value.astimezone()
    return resolved_value.strftime("%b %d, %Y %I:%M %p")


def format_detected_language_label(language_code: Optional[str]) -> Optional[str]:
    normalized_code = trimmed_non_empty(language_code)
    if normalized_code is None:
        return None

    lowered_code = normalized_code.lower()
    display_name = LANGUAGE_DISPLAY_NAMES.get(lowered_code)
    if display_name is None:
        return f"Detected: {lowered_code.upper()}"

    return f"Detected: {display_name} ({lowered_code.upper()})"


def ensure_session_state(runtime: RuntimeDiagnostics) -> None:
    st = get_streamlit()

    defaults = {
        "_heatwave_initialized": True,
        "backend_base_url": runtime.base_url,
        "backend_base_url_dirty": False,
        "run_stamp": runtime.run_stamp,
        "launch_source": runtime.launch_source,
        "prompt_log_path": runtime.prompt_log_path,
        "has_loaded": False,
        "last_requested_search": "",
        "search_query": "",
        "records": [],
        "app_info": None,
        "selected_record_id": None,
        "active_record_id": None,
        "selected_detail": None,
        "selected_image_bytes": None,
        "banner_message": None,
        "library_error_message": None,
        "detail_error_message": None,
        "description_draft": "",
        "description_generation_prompt": "",
        "description_error_message": None,
        "insight_prompt": "",
        "insight_text": None,
        "insight_detected_language": None,
        "insight_error_message": None,
        "show_upload_panel": False,
        "show_settings_panel": False,
        "refresh_requested": False,
        "preferred_selection_id": None,
        "upload_widget_nonce": 0,
        "upload_name": "",
        "upload_description_prompt": "",
        "upload_description": "",
        "upload_error_message": None,
    }

    for key, value in defaults.items():
        if key not in st.session_state:
            st.session_state[key] = value


def mark_backend_base_url_dirty() -> None:
    get_streamlit().session_state.backend_base_url_dirty = True


def persist_backend_base_url_if_needed() -> None:
    st = get_streamlit()
    if not st.session_state.backend_base_url_dirty:
        return

    save_persisted_base_url(st.session_state.backend_base_url)
    st.session_state.backend_base_url_dirty = False


def reset_to_default_backend_url() -> None:
    st = get_streamlit()
    st.session_state.backend_base_url = default_base_url_from_environment()
    save_persisted_base_url(st.session_state.backend_base_url)
    st.session_state.backend_base_url_dirty = False


def make_backend_client() -> BackendClient:
    st = get_streamlit()
    return BackendClient(st.session_state.backend_base_url)


def upload_key(field: str) -> str:
    st = get_streamlit()
    return f"{field}_{st.session_state.upload_widget_nonce}"


def clear_upload_state() -> None:
    st = get_streamlit()
    st.session_state.upload_name = ""
    st.session_state.upload_description_prompt = ""
    st.session_state.upload_description = ""
    st.session_state.upload_error_message = None
    st.session_state.upload_widget_nonce += 1


def ensure_upload_defaults() -> None:
    st = get_streamlit()
    for field_name in ("upload_name", "upload_description_prompt", "upload_description"):
        key = upload_key(field_name)
        if key not in st.session_state:
            st.session_state[key] = st.session_state.get(field_name, "")


def capture_upload_state() -> None:
    st = get_streamlit()
    st.session_state.upload_name = st.session_state.get(upload_key("upload_name"), "")
    st.session_state.upload_description_prompt = st.session_state.get(
        upload_key("upload_description_prompt"),
        "",
    )
    st.session_state.upload_description = st.session_state.get(
        upload_key("upload_description"),
        "",
    )


def reset_selection_dependent_state() -> None:
    st = get_streamlit()
    st.session_state.insight_prompt = ""
    st.session_state.insight_text = None
    st.session_state.insight_detected_language = None
    st.session_state.insight_error_message = None
    st.session_state.description_generation_prompt = ""
    st.session_state.description_error_message = None


def clear_selection() -> None:
    st = get_streamlit()
    st.session_state.selected_record_id = None
    st.session_state.active_record_id = None
    st.session_state.selected_detail = None
    st.session_state.selected_image_bytes = None
    st.session_state.detail_error_message = None
    st.session_state.description_draft = ""
    st.session_state.description_generation_prompt = ""
    st.session_state.description_error_message = None
    st.session_state.insight_prompt = ""
    st.session_state.insight_text = None
    st.session_state.insight_detected_language = None
    st.session_state.insight_error_message = None


def apply_loaded_detail(detail: ImageDetail) -> None:
    st = get_streamlit()
    st.session_state.selected_detail = detail
    st.session_state.description_draft = detail.description or ""
    st.session_state.description_error_message = None


def resolved_selection(
    records: list[ImageSummary],
    current_selection: Optional[int],
    *,
    preferred_selection: Optional[int] = None,
) -> Optional[int]:
    candidate = preferred_selection if preferred_selection is not None else current_selection
    if candidate is not None and any(record.id == candidate for record in records):
        return candidate
    return records[0].id if records else None


def load_detail(record_id: int) -> None:
    st = get_streamlit()

    try:
        client = make_backend_client()
    except BackendClientError as exc:
        st.session_state.detail_error_message = str(exc)
        return

    try:
        detail = client.fetch_image(record_id)
        image_bytes = client.fetch_image_content(record_id)
    except BackendClientError as exc:
        if st.session_state.selected_record_id == record_id:
            st.session_state.selected_detail = None
            st.session_state.selected_image_bytes = None
            st.session_state.active_record_id = None
            st.session_state.detail_error_message = str(exc)
        return

    if st.session_state.selected_record_id != record_id:
        return

    apply_loaded_detail(detail)
    st.session_state.selected_image_bytes = image_bytes
    st.session_state.active_record_id = record_id
    st.session_state.detail_error_message = None


def refresh_library(*, preferred_selection: Optional[int] = None) -> None:
    st = get_streamlit()
    current_query = st.session_state.search_query
    st.session_state.last_requested_search = current_query
    st.session_state.has_loaded = True

    validation_message = validate_base_url(st.session_state.backend_base_url)
    if validation_message is not None:
        st.session_state.library_error_message = validation_message
        return

    try:
        client = make_backend_client()
        records = client.fetch_images(current_query.strip())
        app_info = client.fetch_app_info()
    except BackendClientError as exc:
        st.session_state.library_error_message = str(exc)
        return

    previous_selection = st.session_state.selected_record_id

    st.session_state.records = records
    st.session_state.app_info = app_info
    st.session_state.library_error_message = None

    next_selection = resolved_selection(
        records,
        previous_selection,
        preferred_selection=preferred_selection,
    )
    if next_selection is None:
        clear_selection()
        return

    st.session_state.selected_record_id = next_selection
    if next_selection != previous_selection:
        reset_selection_dependent_state()

    load_detail(next_selection)


def maybe_refresh_library() -> None:
    st = get_streamlit()

    needs_refresh = (
        not st.session_state.has_loaded
        or st.session_state.refresh_requested
        or st.session_state.search_query != st.session_state.last_requested_search
    )
    if not needs_refresh:
        return

    preferred_selection = st.session_state.preferred_selection_id
    st.session_state.refresh_requested = False
    st.session_state.preferred_selection_id = None

    spinner_text = "Refreshing image library..." if st.session_state.has_loaded else "Loading image library..."
    with st.spinner(spinner_text):
        refresh_library(preferred_selection=preferred_selection)


def inject_styles(st) -> None:
    st.markdown(
        """
        <style>
        .stApp {
            background:
                radial-gradient(circle at top left, rgba(195, 229, 255, 0.70), transparent 34%),
                radial-gradient(circle at top right, rgba(255, 228, 212, 0.58), transparent 28%),
                linear-gradient(180deg, #f7f8fb 0%, #eef2f7 100%);
            color: #1d1d1f;
        }
        .block-container {
            max-width: 1360px;
            padding-top: 1.6rem;
            padding-bottom: 3rem;
        }
        h1, h2, h3, p, div, span, label {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif;
        }
        div[data-testid="stVerticalBlockBorderWrapper"] {
            border-radius: 24px;
            border: 1px solid rgba(17, 17, 17, 0.06);
            background: rgba(255, 255, 255, 0.76);
            box-shadow: 0 18px 54px rgba(15, 23, 42, 0.08);
            backdrop-filter: blur(18px);
        }
        .stButton > button {
            border-radius: 999px;
            border: none;
            min-height: 2.85rem;
            font-weight: 600;
            box-shadow: 0 10px 24px rgba(15, 23, 42, 0.08);
        }
        .stButton > button[kind="primary"] {
            background: linear-gradient(180deg, #1c7ef6 0%, #0a62d0 100%);
            color: white;
        }
        div[data-testid="stTextInputRootElement"] input,
        div[data-testid="stTextArea"] textarea,
        div[data-testid="stFileUploader"] section {
            border-radius: 18px !important;
            border: 1px solid rgba(17, 17, 17, 0.08) !important;
            background: rgba(255, 255, 255, 0.92) !important;
        }
        div[data-testid="stImage"] img {
            border-radius: 22px;
        }
        .app-heading {
            padding: 0.1rem 0 0.6rem 0;
        }
        .app-heading p {
            margin: 0.45rem 0 0 0;
            color: #5f636b;
            line-height: 1.55;
        }
        .section-eyebrow {
            margin: 0 0 0.55rem 0;
            font-size: 0.76rem;
            letter-spacing: 0.16em;
            text-transform: uppercase;
            color: #7b8088;
        }
        .metric-pills {
            display: flex;
            gap: 0.7rem;
            flex-wrap: wrap;
            margin: 0.2rem 0 1rem 0;
        }
        .metric-pill {
            display: inline-flex;
            flex-direction: column;
            gap: 0.12rem;
            padding: 0.58rem 0.86rem;
            border-radius: 18px;
            background: rgba(255, 255, 255, 0.84);
            border: 1px solid rgba(17, 17, 17, 0.06);
        }
        .metric-pill-label {
            font-size: 0.68rem;
            letter-spacing: 0.12em;
            text-transform: uppercase;
            color: #7b8088;
        }
        .metric-pill-value {
            font-size: 0.94rem;
            font-weight: 600;
            color: #1d1d1f;
        }
        .quiet-empty {
            padding: 1.6rem 1.1rem;
            border-radius: 22px;
            border: 1px dashed rgba(17, 17, 17, 0.12);
            background: rgba(255, 255, 255, 0.54);
            text-align: center;
        }
        .quiet-empty strong {
            display: block;
            font-size: 1.02rem;
            color: #1d1d1f;
            margin-bottom: 0.38rem;
        }
        .quiet-empty span {
            color: #6a6f78;
            line-height: 1.55;
        }
        .language-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            padding: 0.42rem 0.76rem;
            border-radius: 999px;
            background: rgba(8, 84, 173, 0.10);
            border: 1px solid rgba(8, 84, 173, 0.18);
            color: #0854ad;
            font-size: 0.86rem;
            font-weight: 600;
            margin-bottom: 0.85rem;
        }
        .record-meta {
            margin: 0.08rem 0 0.55rem 0;
            color: #6a6f78;
            font-size: 0.84rem;
            line-height: 1.45;
        }
        .runtime-footer {
            margin-top: 1rem;
            color: #6a6f78;
            font-size: 0.8rem;
            line-height: 1.45;
        }
        div[role="radiogroup"] label p {
            white-space: pre-line;
            line-height: 1.35;
        }
        </style>
        """,
        unsafe_allow_html=True,
    )


def render_empty_state(container, title: str, copy: str) -> None:
    container.markdown(
        f"""
        <div class="quiet-empty">
            <strong>{html.escape(title)}</strong>
            <span>{html.escape(copy)}</span>
        </div>
        """,
        unsafe_allow_html=True,
    )


def render_metric_pills(container, record_count: int, model_id: str) -> None:
    container.markdown(
        f"""
        <div class="metric-pills">
            <div class="metric-pill">
                <span class="metric-pill-label">Images</span>
                <span class="metric-pill-value">{record_count}</span>
            </div>
            <div class="metric-pill">
                <span class="metric-pill-label">Model</span>
                <span class="metric-pill-value">{html.escape(model_id)}</span>
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )


def render_sidebar_header(st) -> None:
    st.sidebar.markdown(
        """
        <div class="app-heading">
            <p class="section-eyebrow">Image Library</p>
            <h2>Review, describe, and inspect records.</h2>
        </div>
        """,
        unsafe_allow_html=True,
    )

    action_cols = st.sidebar.columns(3)
    if action_cols[0].button("Upload", use_container_width=True):
        st.session_state.show_upload_panel = not st.session_state.show_upload_panel

    if action_cols[1].button("Refresh", use_container_width=True):
        st.session_state.refresh_requested = True

    if action_cols[2].button("Settings", use_container_width=True):
        st.session_state.show_settings_panel = not st.session_state.show_settings_panel

    st.sidebar.text_input(
        "Search library",
        key="search_query",
        placeholder=DEFAULT_SEARCH_PLACEHOLDER,
    )


def render_settings_panel(st) -> None:
    if not st.session_state.show_settings_panel:
        return

    with st.sidebar.expander("Settings", expanded=True):
        st.caption("The app stores only the backend URL locally.")
        st.text_input(
            "Backend URL",
            key="backend_base_url",
            on_change=mark_backend_base_url_dirty,
        )
        validation_message = validate_base_url(st.session_state.backend_base_url)
        if validation_message is not None:
            st.error(validation_message)
        else:
            st.caption("Database credentials remain on the FastAPI backend.")

        diag_cols = st.columns(3)
        diag_cols[0].caption("Run Stamp")
        diag_cols[0].code(st.session_state.run_stamp)
        diag_cols[1].caption("Launch Source")
        diag_cols[1].code(st.session_state.launch_source)
        diag_cols[2].caption("Prompt Log")
        diag_cols[2].code(st.session_state.prompt_log_path or "Disabled")

        button_cols = st.columns(2)
        if button_cols[0].button("Reset to Default", use_container_width=True):
            reset_to_default_backend_url()
            st.session_state.refresh_requested = True
            st.rerun()

        if button_cols[1].button("Refresh Data", use_container_width=True):
            st.session_state.refresh_requested = True


def render_sidebar_library(st) -> None:
    app_info = st.session_state.app_info
    record_count = app_info.record_count if app_info is not None else len(st.session_state.records)
    model_id = app_info.ai_model_id if app_info is not None else "Waiting"
    render_metric_pills(st.sidebar, record_count, model_id)

    if st.session_state.banner_message:
        st.sidebar.success(st.session_state.banner_message)
        if st.sidebar.button("Dismiss", key="dismiss_banner", use_container_width=True):
            st.session_state.banner_message = None
            st.rerun()

    if st.session_state.library_error_message:
        st.sidebar.error(st.session_state.library_error_message)

    if st.session_state.records:
        for record in st.session_state.records:
            is_selected = record.id == st.session_state.selected_record_id
            button_type = "primary" if is_selected else "secondary"
            if st.sidebar.button(
                record.image_name,
                key=f"library_row_{record.id}",
                use_container_width=True,
                type=button_type,
            ):
                if record.id != st.session_state.selected_record_id:
                    st.session_state.selected_record_id = record.id
                    reset_selection_dependent_state()
                    with st.spinner("Loading image detail..."):
                        load_detail(record.id)
                    st.rerun()

            st.sidebar.markdown(
                f"""
                <div class="record-meta">
                    #{record.id} • {html.escape(record.original_filename)}<br/>
                    {record.base64_length:,} base64 chars
                </div>
                """,
                unsafe_allow_html=True,
            )
    elif not st.session_state.library_error_message:
        render_empty_state(
            st.sidebar,
            "No Images Yet",
            "Upload an image or adjust the current search.",
        )

    st.sidebar.markdown(
        f"""
        <div class="runtime-footer">
            <strong>Run Stamp</strong><br/>
            <code>{html.escape(st.session_state.run_stamp)}</code>
        </div>
        """,
        unsafe_allow_html=True,
    )


def render_app_header(st) -> None:
    st.markdown(
        """
        <div class="app-heading">
            <p class="section-eyebrow">HeatWave Image Intelligence</p>
            <h1>Streamlit parity for the native macOS workflow.</h1>
            <p>
                The fallback app now talks to the same FastAPI backend as the Swift client, so
                uploads, descriptions, insights, and runtime diagnostics stay aligned.
            </p>
        </div>
        """,
        unsafe_allow_html=True,
    )


def current_uploaded_file():
    st = get_streamlit()
    return st.session_state.get(upload_key("upload_file"))


def render_upload_panel(st) -> None:
    if not st.session_state.show_upload_panel:
        return

    ensure_upload_defaults()
    capture_upload_state()

    with st.container(border=True):
        st.markdown("### Upload Image")
        st.caption("Name the image, attach a file, then save it to the library.")

        form_col, preview_col = st.columns([0.95, 1.05], gap="large")

        with form_col:
            st.text_input(
                "Image Name",
                key=upload_key("upload_name"),
                placeholder="Image name",
            )
            st.file_uploader(
                "Choose Image",
                type=IMAGE_UPLOAD_TYPES,
                key=upload_key("upload_file"),
            )

            action_cols = st.columns([0.55, 0.45])
            if action_cols[0].button(
                "Auto-Generate",
                key="upload_generate_description",
                use_container_width=True,
                disabled=current_uploaded_file() is None,
            ):
                capture_upload_state()
                uploaded_file = current_uploaded_file()
                if uploaded_file is None:
                    st.session_state.upload_error_message = (
                        "Choose an image before generating a description."
                    )
                else:
                    try:
                        client = make_backend_client()
                        with st.spinner("Generating upload description..."):
                            response = client.generate_upload_description(
                                filename=uploaded_file.name or "uploaded-image",
                                mime_type=trimmed_non_empty(uploaded_file.type),
                                image_bytes=uploaded_file.getvalue(),
                                prompt=st.session_state.upload_description_prompt.strip(),
                            )
                        st.session_state.upload_description = response.description
                        st.session_state[upload_key("upload_description")] = response.description
                        st.session_state.upload_error_message = None
                        st.rerun()
                    except BackendClientError as exc:
                        st.session_state.upload_error_message = str(exc)

            st.text_area(
                "Description Prompt",
                key=upload_key("upload_description_prompt"),
                height=84,
                placeholder=UPLOAD_DESCRIPTION_PROMPT_PLACEHOLDER,
            )
            st.text_area(
                "Description",
                key=upload_key("upload_description"),
                height=180,
                placeholder=UPLOAD_DESCRIPTION_PLACEHOLDER,
            )

            if st.session_state.upload_error_message:
                st.error(st.session_state.upload_error_message)

            footer_cols = st.columns([0.42, 0.58])
            if footer_cols[0].button(
                "Cancel",
                key="cancel_upload_panel",
                use_container_width=True,
            ):
                clear_upload_state()
                st.session_state.show_upload_panel = False
                st.rerun()

            can_save_upload = (
                current_uploaded_file() is not None
                and bool(st.session_state.upload_name.strip())
                and bool(st.session_state.upload_description.strip())
            )
            if footer_cols[1].button(
                "Save To Library",
                key="save_upload_panel",
                type="primary",
                use_container_width=True,
                disabled=not can_save_upload,
            ):
                capture_upload_state()
                uploaded_file = current_uploaded_file()
                if uploaded_file is None:
                    st.session_state.upload_error_message = "Choose an image before saving."
                else:
                    try:
                        client = make_backend_client()
                        with st.spinner("Saving image to the library..."):
                            created = client.upload_image(
                                image_name=st.session_state.upload_name.strip(),
                                filename=uploaded_file.name or "uploaded-image",
                                mime_type=trimmed_non_empty(uploaded_file.type),
                                image_bytes=uploaded_file.getvalue(),
                                description=st.session_state.upload_description.strip(),
                            )
                        st.session_state.banner_message = (
                            f'Added "{created.image_name}" to the library.'
                        )
                        clear_upload_state()
                        st.session_state.show_upload_panel = False
                        st.session_state.preferred_selection_id = created.id
                        st.session_state.refresh_requested = True
                        st.rerun()
                    except BackendClientError as exc:
                        st.session_state.upload_error_message = str(exc)

        with preview_col:
            uploaded_file = current_uploaded_file()
            if uploaded_file is None:
                render_empty_state(
                    st,
                    "Preview Appears Here",
                    "Import an image and give it a name to prepare it for upload.",
                )
            else:
                uploaded_bytes = uploaded_file.getvalue()
                try:
                    preview = detect_image_details(uploaded_bytes)
                except Exception as exc:
                    st.error(f"Unable to preview the selected image: {exc}")
                else:
                    preview_name = st.session_state.upload_name.strip() or uploaded_file.name
                    st.image(uploaded_bytes, caption=preview_name, use_container_width=True)
                    st.caption(
                        f"{preview.format_name} | {preview.width}x{preview.height} | "
                        f"{(trimmed_non_empty(uploaded_file.type) or 'application/octet-stream')} | "
                        f"{len(uploaded_bytes):,} bytes"
                    )


def render_image_card(st) -> None:
    with st.container(border=True):
        st.markdown("### Preview")
        image_bytes = st.session_state.selected_image_bytes
        if image_bytes:
            try:
                st.image(image_bytes, use_container_width=True)
            except Exception:
                render_empty_state(
                    st,
                    "Image Unavailable",
                    "The selected image content could not be rendered.",
                )
        else:
            render_empty_state(
                st,
                "Image Unavailable",
                "The selected image content could not be rendered.",
            )


def render_description_card(st, detail: ImageDetail) -> None:
    with st.container(border=True):
        st.markdown("### Description")
        st.caption("Stored with the image and used as context for later AI insight generation.")

        action_cols = st.columns(2)
        if action_cols[0].button(
            "Update Description",
            key="generate_existing_description",
            use_container_width=True,
        ):
            if st.session_state.selected_record_id is None:
                st.session_state.description_error_message = (
                    "Choose an image before generating a description."
                )
            else:
                try:
                    client = make_backend_client()
                    with st.spinner("Generating updated description..."):
                        updated_detail = client.generate_image_description(
                            record_id=st.session_state.selected_record_id,
                            prompt=st.session_state.description_generation_prompt.strip(),
                        )
                    apply_loaded_detail(updated_detail)
                    st.session_state.selected_detail = updated_detail
                    st.rerun()
                except BackendClientError as exc:
                    st.session_state.description_error_message = str(exc)

        if action_cols[1].button(
            "Save Description",
            key="save_existing_description",
            use_container_width=True,
            disabled=not st.session_state.description_draft.strip(),
        ):
            if st.session_state.selected_record_id is None:
                st.session_state.description_error_message = (
                    "Choose an image before saving a description."
                )
            elif not st.session_state.description_draft.strip():
                st.session_state.description_error_message = "Image description is required."
            else:
                try:
                    client = make_backend_client()
                    with st.spinner("Saving image description..."):
                        updated_detail = client.update_image_description(
                            record_id=st.session_state.selected_record_id,
                            description=st.session_state.description_draft.strip(),
                        )
                    apply_loaded_detail(updated_detail)
                    st.session_state.selected_detail = updated_detail
                    st.rerun()
                except BackendClientError as exc:
                    st.session_state.description_error_message = str(exc)

        st.text_area(
            "Generation Prompt",
            key="description_generation_prompt",
            height=88,
            placeholder=DETAIL_DESCRIPTION_PROMPT_PLACEHOLDER,
        )
        st.text_area(
            "Stored Description",
            key="description_draft",
            height=200,
            placeholder=detail.description or DETAIL_DESCRIPTION_PLACEHOLDER,
        )

        if st.session_state.description_error_message:
            st.error(st.session_state.description_error_message)


def render_metadata_card(st, detail: ImageDetail) -> None:
    with st.container(border=True):
        st.markdown("### Metadata")
        left_col, right_col = st.columns(2)

        left_col.caption("Record")
        left_col.write(f"#{detail.id}")
        left_col.caption("Original File")
        left_col.write(detail.original_filename)
        left_col.caption("Created")
        left_col.write(format_timestamp(detail.created_at))

        right_col.caption("MIME Type")
        right_col.write(detail.mime_type)
        right_col.caption("Payload")
        right_col.write(f"{detail.base64_length:,} chars")
        right_col.caption("Updated")
        right_col.write(format_timestamp(detail.updated_at))


def render_insight_card(st) -> None:
    with st.container(border=True):
        st.markdown("### AI Insight")
        st.caption("Ask a focused question about the selected image.")
        st.text_area(
            "Prompt",
            key="insight_prompt",
            height=96,
            placeholder=DEFAULT_INSIGHT_PROMPT,
        )

        if st.button(
            "Generate Insight",
            key="generate_insight",
            type="primary",
            use_container_width=True,
            disabled=(
                st.session_state.selected_record_id is None
                or not st.session_state.insight_prompt.strip()
            ),
        ):
            if st.session_state.selected_record_id is None:
                st.session_state.insight_error_message = (
                    "Choose an image before asking for insight."
                )
            elif not st.session_state.insight_prompt.strip():
                st.session_state.insight_error_message = (
                    "Enter a prompt before generating an AI response."
                )
            else:
                try:
                    client = make_backend_client()
                    with st.spinner("Generating insight..."):
                        response = client.generate_insight(
                            record_id=st.session_state.selected_record_id,
                            prompt=st.session_state.insight_prompt.strip(),
                        )
                    st.session_state.insight_text = response.text
                    st.session_state.insight_detected_language = response.detected_language
                    st.session_state.insight_error_message = None
                except BackendClientError as exc:
                    st.session_state.insight_text = None
                    st.session_state.insight_detected_language = None
                    st.session_state.insight_error_message = str(exc)

        if st.session_state.insight_error_message:
            st.error(st.session_state.insight_error_message)

        language_label = format_detected_language_label(
            st.session_state.insight_detected_language
        )
        if language_label:
            st.markdown(
                f'<div class="language-badge">{html.escape(language_label)}</div>',
                unsafe_allow_html=True,
            )

        if st.session_state.insight_text:
            st.markdown(st.session_state.insight_text)
        else:
            render_empty_state(
                st,
                "No insight generated yet",
                "Enter a prompt and run insight generation to see the model response.",
            )


def render_detail_pane(st) -> None:
    detail = st.session_state.selected_detail
    if detail is None:
        if st.session_state.detail_error_message:
            with st.container(border=True):
                st.error(st.session_state.detail_error_message)
        else:
            render_empty_state(
                st,
                "Select an Image",
                "Choose a record from the library to review metadata and ask for an AI insight.",
            )
        return

    st.markdown(f"## {html.escape(detail.image_name)}")
    st.caption(
        f"{detail.original_filename} • {detail.mime_type} • #{detail.id}"
    )

    left_col, right_col = st.columns([1.55, 1.0], gap="large")

    with left_col:
        render_image_card(st)
        render_description_card(st, detail)
        render_metadata_card(st, detail)

    with right_col:
        render_insight_card(st)


def run_streamlit_app() -> None:
    st = get_streamlit()
    st.set_page_config(
        page_title="HeatWave Image Intelligence",
        layout="wide",
        initial_sidebar_state="expanded",
    )

    load_dotenv_file()
    runtime = build_runtime_diagnostics(os.environ, load_persisted_base_url())
    ensure_session_state(runtime)
    inject_styles(st)

    render_sidebar_header(st)
    render_settings_panel(st)
    persist_backend_base_url_if_needed()
    maybe_refresh_library()
    render_sidebar_library(st)

    render_app_header(st)
    render_upload_panel(st)
    render_detail_pane(st)


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
