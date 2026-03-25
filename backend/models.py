from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


def to_camel(value: str) -> str:
    head, *tail = value.split("_")
    return head + "".join(part.title() for part in tail)


class APIModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class ErrorResponse(BaseModel):
    error: str


class AppInfo(APIModel):
    ai_model_id: str
    record_count: int


class ImageSummary(APIModel):
    id: int
    image_name: str
    original_filename: str
    mime_type: str
    base64_length: int
    created_at: datetime
    updated_at: datetime


class ImageDetail(ImageSummary):
    description: Optional[str] = None


class InsightRequest(APIModel):
    prompt: str


class InsightResponse(APIModel):
    text: str
    detected_language: Optional[str] = None


class DescriptionUpdateRequest(APIModel):
    description: str


class DescriptionGenerationRequest(APIModel):
    prompt: str = ""


class GeneratedDescriptionResponse(APIModel):
    description: str
    detected_language: Optional[str] = None
