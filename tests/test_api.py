from __future__ import annotations

import base64
from copy import deepcopy
from datetime import datetime, timedelta

from fastapi.testclient import TestClient

from backend.config import AppConfig
from backend.errors import NotFoundError, ValidationError
from backend.images import ImagePayload, ImageService
from backend.main import create_app
from backend.repository import InsightGenerationResult

PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jq1cAAAAASUVORK5CYII="
)


def make_config() -> AppConfig:
    return AppConfig(
        db_host="localhost",
        db_port=3306,
        db_user="user",
        db_password="password",
        db_schema="image_registry",
        db_table="image_assets",
        ai_model_id="model-id",
        ai_language="en",
    )


class InMemoryRepository:
    def __init__(self) -> None:
        self.ensure_called = False
        self.saved_payloads: list[tuple[ImagePayload, str]] = []
        self.insight_requests: list[tuple[int, str]] = []
        self.generated_upload_description_requests: list[tuple[str, str]] = []
        self.updated_description_requests: list[tuple[int, str]] = []
        self.generated_description_requests: list[tuple[int, str]] = []
        self.next_id = 1
        self.records: dict[int, dict] = {}

    def ensure_schema_and_table(self) -> None:
        self.ensure_called = True

    def count_records(self) -> int:
        return len(self.records)

    def list_records(self, search: str = "") -> list[dict]:
        values = list(self.records.values())
        if search.strip():
            lowered = search.lower()
            values = [record for record in values if lowered in record["image_name"].lower()]
        return sorted(values, key=lambda record: (record["created_at"], record["id"]), reverse=True)

    def get_record(self, record_id: int, *, include_payload: bool = False) -> dict | None:
        record = self.records.get(record_id)
        if not record:
            return None
        cloned = deepcopy(record)
        if not include_payload:
            cloned.pop("base64_payload", None)
        return cloned

    def get_record_or_404(self, record_id: int, *, include_payload: bool = False) -> dict:
        record = self.get_record(record_id, include_payload=include_payload)
        if not record:
            raise NotFoundError("Image record not found.")
        return record

    def create_image(self, payload: ImagePayload, *, description: str | None = None) -> dict:
        cleaned_description = (description or "").strip()
        if not cleaned_description:
            raise ValidationError("Image description is required.")

        record_id = self.next_id
        self.next_id += 1
        now = datetime(2026, 3, 23, 12, 0, 0) + timedelta(seconds=record_id)
        record = {
            "id": record_id,
            "image_name": payload.image_name,
            "original_filename": payload.original_filename,
            "mime_type": payload.mime_type,
            "description": cleaned_description,
            "base64_length": len(payload.base64_payload),
            "base64_payload": payload.base64_payload,
            "created_at": now,
            "updated_at": now,
        }
        self.records[record_id] = record
        self.saved_payloads.append((payload, cleaned_description))
        return self.get_record_or_404(record_id)

    def generate_upload_description(
        self,
        *,
        base64_payload: str,
        prompt: str,
    ) -> InsightGenerationResult:
        self.generated_upload_description_requests.append((base64_payload, prompt))
        return InsightGenerationResult(
            text="Generated upload description for the selected image.",
            detected_language="en",
        )

    def update_image_description(self, record_id: int, *, description: str) -> dict:
        record = self.records.get(record_id)
        if not record:
            raise NotFoundError("Image record not found.")

        cleaned_description = description.strip()
        if not cleaned_description:
            raise ValidationError("Image description is required.")

        record["description"] = cleaned_description
        record["updated_at"] = record["updated_at"] + timedelta(minutes=1)
        self.updated_description_requests.append((record_id, cleaned_description))
        return self.get_record_or_404(record_id)

    def generate_and_store_description(self, record_id: int, *, prompt: str) -> dict:
        record = self.records.get(record_id)
        if not record:
            raise NotFoundError("Image record not found.")

        cleaned_prompt = prompt.strip()
        if cleaned_prompt:
            description = f"Generated description guided by: {cleaned_prompt}"
        else:
            description = "Generated updated description for the selected image."
        record["description"] = description
        record["updated_at"] = record["updated_at"] + timedelta(minutes=1)
        self.generated_description_requests.append((record_id, cleaned_prompt))
        return self.get_record_or_404(record_id)

    def generate_image_insight_result(
        self,
        record_id: int,
        prompt: str,
    ) -> InsightGenerationResult:
        if record_id not in self.records:
            raise NotFoundError("Image record not found.")
        self.insight_requests.append((record_id, prompt))
        return InsightGenerationResult(
            text="The sky is clear.",
            detected_language="en",
        )


def make_client(repository: InMemoryRepository) -> TestClient:
    app = create_app(
        config=make_config(),
        repository=repository,
        image_service=ImageService(),
    )
    return TestClient(app)


def test_startup_bootstraps_repository() -> None:
    repository = InMemoryRepository()

    with make_client(repository):
        assert repository.ensure_called is True


def test_upload_stores_expected_metadata_payload_and_description() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        response = client.post(
            "/images",
            data={
                "image_name": "Bluebonnet Longhorn",
                "description": "Blue pickup truck parked on a road with wildflowers nearby.",
            },
            files={"file": ("truck.png", PNG_BYTES, "image/png")},
        )

    assert response.status_code == 201
    payload, description = repository.saved_payloads[0]
    assert payload.image_name == "Bluebonnet Longhorn"
    assert payload.original_filename == "truck.png"
    assert payload.mime_type == "image/png"
    assert base64.b64decode(payload.base64_payload) == PNG_BYTES
    assert description == "Blue pickup truck parked on a road with wildflowers nearby."
    assert response.json()["imageName"] == "Bluebonnet Longhorn"
    assert response.json()["description"] == description


def test_upload_without_description_is_rejected() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        response = client.post(
            "/images",
            data={"image_name": "Bluebonnet Longhorn"},
            files={"file": ("truck.png", PNG_BYTES, "image/png")},
        )

    assert response.status_code == 400
    assert response.json() == {"error": "Image description is required."}


def test_invalid_upload_is_rejected() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        response = client.post(
            "/images",
            data={
                "image_name": "Broken",
                "description": "This should fail before saving.",
            },
            files={"file": ("broken.png", b"not-a-real-image", "image/png")},
        )

    assert response.status_code == 400
    assert response.json() == {"error": "Unsupported or corrupt image file."}


def test_list_and_search_return_descending_created_order() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        client.post(
            "/images",
            data={
                "image_name": "Truck",
                "description": "Truck description.",
            },
            files={"file": ("truck.png", PNG_BYTES, "image/png")},
        )
        client.post(
            "/images",
            data={
                "image_name": "Barn",
                "description": "Barn description.",
            },
            files={"file": ("barn.png", PNG_BYTES, "image/png")},
        )

        all_records = client.get("/images")
        filtered_records = client.get("/images", params={"search": "Barn"})

    assert all_records.status_code == 200
    assert [record["imageName"] for record in all_records.json()] == ["Barn", "Truck"]
    assert filtered_records.status_code == 200
    assert [record["imageName"] for record in filtered_records.json()] == ["Barn"]


def test_missing_record_endpoints_return_404() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        detail_response = client.get("/images/999")
        content_response = client.get("/images/999/content")
        insight_response = client.post("/images/999/insights", json={"prompt": "Describe it"})
        update_description_response = client.put(
            "/images/999/description",
            json={"description": "Updated description"},
        )
        generate_description_response = client.post(
            "/images/999/description/generate",
            json={"prompt": "Refresh it"},
        )

    assert detail_response.status_code == 404
    assert detail_response.json() == {"error": "Image record not found."}
    assert content_response.status_code == 404
    assert content_response.json() == {"error": "Image record not found."}
    assert insight_response.status_code == 404
    assert insight_response.json() == {"error": "Image record not found."}
    assert update_description_response.status_code == 404
    assert update_description_response.json() == {"error": "Image record not found."}
    assert generate_description_response.status_code == 404
    assert generate_description_response.json() == {"error": "Image record not found."}


def test_content_endpoint_returns_raw_image_bytes() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        created = client.post(
            "/images",
            data={
                "image_name": "Preview",
                "description": "Preview description.",
            },
            files={"file": ("preview.png", PNG_BYTES, "image/png")},
        )
        record_id = created.json()["id"]
        response = client.get(f"/images/{record_id}/content")

    assert response.status_code == 200
    assert response.content == PNG_BYTES
    assert response.headers["content-type"].startswith("image/png")


def test_generate_upload_description_returns_text_and_detected_language() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        response = client.post(
            "/descriptions/generate-upload",
            data={"prompt": "Focus on the main subject"},
            files={"file": ("preview.png", PNG_BYTES, "image/png")},
        )

    assert response.status_code == 200
    assert response.json() == {
        "description": "Generated upload description for the selected image.",
        "detectedLanguage": "en",
    }
    assert repository.generated_upload_description_requests[0][1] == "Focus on the main subject"


def test_update_description_endpoint_returns_updated_detail() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        created = client.post(
            "/images",
            data={
                "image_name": "Preview",
                "description": "Original description.",
            },
            files={"file": ("preview.png", PNG_BYTES, "image/png")},
        )
        record_id = created.json()["id"]
        response = client.put(
            f"/images/{record_id}/description",
            json={"description": "Updated reusable description."},
        )

    assert response.status_code == 200
    assert response.json()["description"] == "Updated reusable description."
    assert repository.updated_description_requests == [(record_id, "Updated reusable description.")]


def test_generate_description_endpoint_returns_updated_detail() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        created = client.post(
            "/images",
            data={
                "image_name": "Preview",
                "description": "Original description.",
            },
            files={"file": ("preview.png", PNG_BYTES, "image/png")},
        )
        record_id = created.json()["id"]
        response = client.post(
            f"/images/{record_id}/description/generate",
            json={"prompt": "Focus on the truck and field"},
        )

    assert response.status_code == 200
    assert response.json()["description"] == "Generated description guided by: Focus on the truck and field"
    assert repository.generated_description_requests == [(record_id, "Focus on the truck and field")]


def test_insight_endpoint_returns_text_and_detected_language() -> None:
    repository = InMemoryRepository()

    with make_client(repository) as client:
        created = client.post(
            "/images",
            data={
                "image_name": "Preview",
                "description": "Preview description.",
            },
            files={"file": ("preview.png", PNG_BYTES, "image/png")},
        )
        record_id = created.json()["id"]
        response = client.post(
            f"/images/{record_id}/insights",
            json={"prompt": "Describe it"},
        )

    assert response.status_code == 200
    assert response.json() == {
        "text": "The sky is clear.",
        "detectedLanguage": "en",
    }
