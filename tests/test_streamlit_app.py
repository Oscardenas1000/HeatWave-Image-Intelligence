from __future__ import annotations

from datetime import datetime, timezone

from heatwave_image_app import (
    DEFAULT_BACKEND_URL,
    ImageSummary,
    RuntimeDiagnostics,
    build_image_data_url,
    build_runtime_diagnostics,
    build_streamlit_launch_environment,
    format_byte_count,
    format_detected_language_label,
    library_option_label,
    make_fallback_run_stamp,
    resolved_selection,
    should_bootstrap_local_backend,
    validate_base_url,
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


def test_make_fallback_run_stamp_matches_direct_run_style() -> None:
    run_stamp = make_fallback_run_stamp(
        datetime(2026, 3, 25, 18, 7, 9, tzinfo=timezone.utc)
    )

    assert run_stamp == "direct-2026-03-25T180709Z"


def test_build_runtime_diagnostics_prefers_environment_override() -> None:
    diagnostics = build_runtime_diagnostics(
        {
            "HEATWAVE_API_BASE_URL": "http://127.0.0.1:8123",
            "HEATWAVE_BUILD_STAMP": "streamlit-mock-20260325T180709Z",
            "HEATWAVE_LAUNCH_SOURCE": "streamlit-local-mock-backend",
            "HEATWAVE_PROMPT_LOG_PATH": "/tmp/heatwave-prompt.log",
        },
        persisted_base_url="http://persisted.example:9000",
    )

    assert diagnostics == RuntimeDiagnostics(
        base_url="http://127.0.0.1:8123",
        run_stamp="streamlit-mock-20260325T180709Z",
        launch_source="streamlit-local-mock-backend",
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


def test_library_option_label_includes_name_and_record_id() -> None:
    assert library_option_label(make_summary(7)) == "Image 7 (#7)"


def test_format_byte_count_scales_human_readably() -> None:
    assert format_byte_count(900) == "900 B"
    assert format_byte_count(2048) == "2.0 KB"
    assert format_byte_count(5 * 1024 * 1024) == "5.0 MB"


def test_build_image_data_url_encodes_payload() -> None:
    assert build_image_data_url(b"abc", "image/png") == "data:image/png;base64,YWJj"


def test_should_bootstrap_local_backend_only_for_local_http_urls_with_ports() -> None:
    assert should_bootstrap_local_backend("http://127.0.0.1:8000") is True
    assert should_bootstrap_local_backend("http://localhost:8123") is True
    assert should_bootstrap_local_backend("http://127.0.0.1") is False
    assert should_bootstrap_local_backend("https://127.0.0.1:8000") is False
    assert should_bootstrap_local_backend("http://example.com:8000") is False


def test_resolved_selection_prefers_current_then_first_visible() -> None:
    records = [make_summary(2), make_summary(1)]

    assert resolved_selection(records, 2) == 2
    assert resolved_selection(records, 999) == 2
    assert resolved_selection(records, 999, preferred_selection=1) == 1
    assert resolved_selection([], 2) is None


def test_format_detected_language_label_uses_name_when_known() -> None:
    assert format_detected_language_label("en") == "Detected: English (EN)"
    assert format_detected_language_label("zz") == "Detected: ZZ"


def test_build_streamlit_launch_environment_pins_runtime_values() -> None:
    runtime = RuntimeDiagnostics(
        base_url="http://127.0.0.1:8000",
        run_stamp="direct-2026-03-25T180709Z",
        launch_source="direct-streamlit-run",
        prompt_log_path=None,
    )

    launch_environment = build_streamlit_launch_environment(
        runtime,
        environment={
            "HEATWAVE_API_BASE_URL": "http://example.com:9999",
            "HEATWAVE_PROMPT_LOG_PATH": "/tmp/old.log",
            "OTHER_ENV": "kept",
        },
    )

    assert launch_environment["HEATWAVE_API_BASE_URL"] == "http://127.0.0.1:8000"
    assert launch_environment["HEATWAVE_BUILD_STAMP"] == "direct-2026-03-25T180709Z"
    assert launch_environment["HEATWAVE_LAUNCH_SOURCE"] == "direct-streamlit-run"
    assert "HEATWAVE_PROMPT_LOG_PATH" not in launch_environment
    assert launch_environment["OTHER_ENV"] == "kept"
