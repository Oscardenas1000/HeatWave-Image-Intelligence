from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from io import BytesIO
from typing import Optional

from backend.errors import BackendError, ValidationError

SUPPORTED_FORMATS = {
    "PNG": "image/png",
    "JPEG": "image/jpeg",
    "WEBP": "image/webp",
    "GIF": "image/gif",
    "BMP": "image/bmp",
}


@dataclass(frozen=True)
class ImagePayload:
    image_name: str
    original_filename: str
    mime_type: str
    base64_payload: str


@dataclass(frozen=True)
class ImageDetails:
    format: str
    width: int
    height: int


class ImageService:
    def detect_image_details(self, image_bytes: bytes) -> ImageDetails:
        from PIL import Image, UnidentifiedImageError  # type: ignore

        try:
            with Image.open(BytesIO(image_bytes)) as image:
                image.load()
                image_format = (image.format or "").upper()
                if image_format not in SUPPORTED_FORMATS:
                    raise ValidationError(
                        "Unsupported image format. Use PNG, JPG, WEBP, GIF, or BMP."
                    )
                return ImageDetails(
                    format=image_format,
                    width=image.width,
                    height=image.height,
                )
        except ValidationError:
            raise
        except (UnidentifiedImageError, OSError) as exc:
            raise ValidationError("Unsupported or corrupt image file.") from exc

    def build_payload_from_upload(
        self,
        *,
        image_name: str,
        original_filename: str,
        declared_mime_type: str | None,
        image_bytes: bytes,
    ) -> tuple[ImagePayload, ImageDetails]:
        cleaned_name = image_name.strip()
        if not cleaned_name:
            raise ValidationError("Image name is required.")
        if not image_bytes:
            raise ValidationError("Image file is empty.")

        details = self.detect_image_details(image_bytes)
        mime_type = SUPPORTED_FORMATS[details.format]
        if declared_mime_type and not declared_mime_type.startswith("image/"):
            raise ValidationError("Uploaded file must be an image.")

        payload = ImagePayload(
            image_name=cleaned_name,
            original_filename=original_filename or "uploaded-image",
            mime_type=mime_type,
            base64_payload=base64.b64encode(image_bytes).decode("ascii"),
        )
        return payload, details

    def clean_base64_text(self, base64_text: str) -> tuple[str, Optional[str]]:
        text = "".join(base64_text.split())
        mime_hint = None

        if text.startswith("data:"):
            header, separator, payload = text.partition(",")
            if not separator or not payload:
                raise BackendError("Stored image payload is incomplete.")
            if ";base64" not in header:
                raise BackendError("Stored image payload is not base64-encoded.")
            mime_hint = header[5:].split(";", 1)[0] or None
            text = payload

        return text, mime_hint

    def decode_base64_text(self, base64_text: str) -> tuple[bytes, str, Optional[str]]:
        cleaned, mime_hint = self.clean_base64_text(base64_text)
        try:
            decoded = base64.b64decode(cleaned, validate=True)
        except binascii.Error as exc:
            raise BackendError("Stored image payload is invalid.") from exc
        return decoded, cleaned, mime_hint
