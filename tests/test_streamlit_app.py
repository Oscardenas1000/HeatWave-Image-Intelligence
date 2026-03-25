from __future__ import annotations

from datetime import datetime, timezone

from heatwave_image_app import (
    DEFAULT_BACKEND_URL,
    RuntimeDiagnostics,
    build_runtime_diagnostics,
    format_detected_language_label,
    make_fallback_run_stamp,
    resolved_selection,
    validate_base_url,
    ImageSummary,
)


def make_summary(record_id: int) -> ImageSummary:
    timestamp = datetime(2026, 3, 25, 12, 0, tzinfo=timezone.utc)
    return ImageSummary(
        id=record_id,
        image_name=f"Image {record_id}",
        original_filename=f"image-{record_id}.png",
        mime_type="image/png",
        base64_length=1024,
        created_at=timestamp,
        updated_at=timestamp,
    )


def test_make_fallback_run_stamp_matches_swift_style() -> None:
    run_stamp = make_fallback_run_stamp(
        datetime(2026, 3, 25, 18, 7, 9, tzinfo=timezone.utc)
    )

    assert run_stamp == "direct-2026-03-25T180709Z"


def test_build_runtime_diagnostics_prefers_environment_override() -> None:
    diagnostics = build_runtime_diagnostics(
        {
            "HEATWAVE_API_BASE_URL": "http://127.0.0.1:8123",
            "HEATWAVE_BUILD_STAMP": "launcher-mock-20260325T180709Z",
            "HEATWAVE_LAUNCH_SOURCE": "run_heatwave_image_intelligence.command --mock-backend",
            "HEATWAVE_PROMPT_LOG_PATH": "/tmp/heatwave-prompt.log",
        },
        persisted_base_url="http://persisted.example:9000",
    )

    assert diagnostics == RuntimeDiagnostics(
        base_url="http://127.0.0.1:8123",
        run_stamp="launcher-mock-20260325T180709Z",
        launch_source="run_heatwave_image_intelligence.command --mock-backend",
        prompt_log_path="/tmp/heatwave-prompt.log",
    )


def test_build_runtime_diagnostics_falls_back_without_environment() -> None:
    diagnostics = build_runtime_diagnostics(
        {},
        persisted_base_url=None,
        now=datetime(2026, 3, 25, 18, 7, 9, tzinfo=timezone.utc),
    )

    assert diagnostics.base_url == DEFAULT_BACKEND_URL
    assert diagnostics.run_stamp == "direct-2026-03-25T180709Z"
    assert diagnostics.launch_source == "direct-streamlit-run"
    assert diagnostics.prompt_log_path is None


def test_validate_base_url_requires_scheme_and_host() -> None:
    assert validate_base_url("127.0.0.1:8000") == (
        "Enter a valid backend URL including the scheme and host."
    )
    assert validate_base_url("http://127.0.0.1:8000") is None


def test_resolved_selection_prefers_current_then_first_visible() -> None:
    records = [make_summary(2), make_summary(1)]

    assert resolved_selection(records, 2) == 2
    assert resolved_selection(records, 999) == 2
    assert resolved_selection(records, 999, preferred_selection=1) == 1
    assert resolved_selection([], 2) is None


def test_format_detected_language_label_uses_name_when_known() -> None:
    assert format_detected_language_label("en") == "Detected: English (EN)"
    assert format_detected_language_label("zz") == "Detected: ZZ"
