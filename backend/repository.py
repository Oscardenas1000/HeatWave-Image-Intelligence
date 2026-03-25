from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any

from backend.bootstrap import SQLBootstrapper
from backend.config import AppConfig, quote_identifier
from backend.database import MySQLDatabase
from backend.errors import AppError, BackendError, NotFoundError, ValidationError
from backend.images import ImagePayload

LANGUAGE_CODE_PATTERN = re.compile(r"[a-z]{2}")


@dataclass(frozen=True)
class InsightGenerationResult:
    text: str
    detected_language: str


def parse_ml_generate_response(raw_response: Any) -> str:
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


def normalize_language_code(raw_response: Any) -> str | None:
    if raw_response is None:
        return None

    normalized = str(raw_response).strip().strip("`'\"").lower()
    if LANGUAGE_CODE_PATTERN.fullmatch(normalized):
        return normalized
    return None


def build_language_detection_prompt(prompt: str, fallback_language: str) -> str:
    return (
        "Identify the dominant natural language used in the user text below. "
        "Respond with only the lowercase ISO 639-1 two-letter code. "
        "Do not add explanation, punctuation, markdown, or quotes. "
        f"If you are unsure, respond with {fallback_language}.\n\n"
        "User text:\n<<<\n"
        f"{prompt}\n"
        ">>>"
    )


def normalize_description_text(description: str | None) -> str | None:
    if description is None:
        return None

    cleaned = description.strip()
    return cleaned or None


class MySQLImageRepository:
    description_column_comment = (
        "User-provided or AI-generated image description used as prompt context"
    )

    def __init__(
        self,
        config: AppConfig,
        *,
        database: MySQLDatabase | Any | None = None,
        bootstrapper: SQLBootstrapper | None = None,
    ) -> None:
        self.config = config
        self.database = database or MySQLDatabase(config)
        self.bootstrapper = bootstrapper or SQLBootstrapper(config)

    @property
    def table_ref(self) -> str:
        return (
            f"{quote_identifier(self.config.db_schema)}."
            f"{quote_identifier(self.config.db_table)}"
        )

    def ensure_schema_and_table(self) -> None:
        self.bootstrapper.run(self.database.execute)
        self.ensure_description_column()

    def ensure_description_column(self) -> None:
        row = self.database.fetch_one(
            """
            SELECT COUNT(*) AS column_count
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = %s
              AND TABLE_NAME = %s
              AND COLUMN_NAME = 'description'
            """,
            (self.config.db_schema, self.config.db_table),
            database=None,
        )
        if int((row or {}).get("column_count", 0)) > 0:
            return

        self.database.execute(
            f"""
            ALTER TABLE {self.table_ref}
            ADD COLUMN description TEXT NULL
            COMMENT %s
            AFTER base64_payload
            """,
            (self.description_column_comment,),
            database=None,
        )

    def count_records(self) -> int:
        row = self.database.fetch_one(
            f"SELECT COUNT(*) AS record_count FROM {self.table_ref}"
        )
        return int((row or {}).get("record_count", 0))

    def list_records(self, name_filter: str = "") -> list[dict[str, Any]]:
        base_query = f"""
            SELECT
                id,
                image_name,
                original_filename,
                mime_type,
                CHAR_LENGTH(base64_payload) AS base64_length,
                created_at,
                updated_at
            FROM {self.table_ref}
        """

        if name_filter.strip():
            return self.database.fetch_all(
                base_query
                + """
                WHERE image_name LIKE %s
                ORDER BY created_at DESC, id DESC
                """,
                (f"%{name_filter.strip()}%",),
            )

        return self.database.fetch_all(
            base_query
            + """
            ORDER BY created_at DESC, id DESC
            """
        )

    def get_record(
        self,
        record_id: int,
        *,
        include_payload: bool = False,
    ) -> dict[str, Any] | None:
        payload_column = ", base64_payload" if include_payload else ""
        rows = self.database.fetch_all(
            f"""
            SELECT
                id,
                image_name,
                original_filename,
                mime_type,
                description,
                CHAR_LENGTH(base64_payload) AS base64_length,
                created_at,
                updated_at
                {payload_column}
            FROM {self.table_ref}
            WHERE id = %s
            """,
            (record_id,),
        )
        return rows[0] if rows else None

    def get_record_or_404(
        self,
        record_id: int,
        *,
        include_payload: bool = False,
    ) -> dict[str, Any]:
        record = self.get_record(record_id, include_payload=include_payload)
        if not record:
            raise NotFoundError("Image record not found.")
        return record

    def create_image(
        self,
        payload: ImagePayload,
        *,
        description: str | None = None,
    ) -> dict[str, Any]:
        normalized_description = normalize_description_text(description)
        if not normalized_description:
            raise ValidationError("Image description is required.")
        new_id = self.database.insert(
            f"""
            INSERT INTO {self.table_ref} (
                image_name,
                original_filename,
                mime_type,
                base64_payload,
                description
            )
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                payload.image_name,
                payload.original_filename,
                payload.mime_type,
                payload.base64_payload,
                normalized_description,
            ),
        )
        record = self.get_record(new_id)
        if not record:
            raise BackendError("Image record could not be reloaded after insert.")
        return record

    def detect_prompt_language(self, cursor: Any, prompt: str) -> str:
        fallback_language = normalize_language_code(self.config.ai_language) or "en"
        if not prompt.strip():
            return fallback_language

        try:
            cursor.execute(
                """
                SELECT sys.ML_GENERATE(
                    %s,
                    JSON_OBJECT(
                        'task', 'generation',
                        'model_id', %s,
                        'language', %s
                    )
                ) AS response
                """,
                (
                    build_language_detection_prompt(prompt, fallback_language),
                    self.config.ai_model_id,
                    fallback_language,
                ),
            )
            row = cursor.fetchone()
        except Exception:
            return fallback_language

        detected_language = normalize_language_code(
            parse_ml_generate_response((row or {}).get("response"))
        )
        return detected_language or fallback_language

    def build_description_generation_prompt(self, prompt: str) -> str:
        guidance = prompt.strip()
        if not guidance:
            return (
                "Generate a reusable description of this image for future AI context. "
                "Focus only on visually observable details. Mention the main subjects, setting, "
                "visible text, colors, layout, and notable relationships between objects when relevant. "
                "Write a clear standalone description in concise prose."
            )

        return (
            "Generate a reusable description of this image for future AI context. "
            "Follow the user's guidance when it is consistent with the visible content. "
            "Keep the result grounded in the image and write a standalone description.\n\n"
            "User guidance:\n"
            f"{guidance}"
        )

    def generate_description_for_base64(
        self,
        cursor: Any,
        *,
        base64_reference_sql: str,
        prompt: str,
    ) -> InsightGenerationResult:
        detected_language = self.detect_prompt_language(cursor, prompt)
        cursor.execute(
            f"""
            SELECT sys.ML_GENERATE(
                %s,
                JSON_OBJECT(
                    'task', 'generation',
                    'model_id', %s,
                    'language', %s,
                    'image', {base64_reference_sql}
                )
            ) AS response
            """,
            (
                self.build_description_generation_prompt(prompt),
                self.config.ai_model_id,
                detected_language,
            ),
        )
        row = cursor.fetchone()
        if not row:
            raise BackendError("HeatWave did not return a response.")

        description = parse_ml_generate_response(row.get("response"))
        normalized_description = normalize_description_text(description)
        if not normalized_description:
            raise BackendError("HeatWave did not return an image description.")

        return InsightGenerationResult(
            text=normalized_description,
            detected_language=detected_language,
        )

    def generate_upload_description(
        self,
        *,
        base64_payload: str,
        prompt: str,
    ) -> InsightGenerationResult:
        conn = self.database.get_connection()
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SET @image_base64 = %s", (base64_payload,))
            return self.generate_description_for_base64(
                cursor,
                base64_reference_sql="@image_base64",
                prompt=prompt,
            )
        except AppError:
            raise
        except Exception as exc:
            raise BackendError(f"Description generation failed: {exc}") from exc
        finally:
            conn.close()

    def update_image_description(
        self,
        record_id: int,
        *,
        description: str,
    ) -> dict[str, Any]:
        normalized_description = normalize_description_text(description)
        if not normalized_description:
            raise ValidationError("Image description is required.")

        self.get_record_or_404(record_id)
        self.database.execute(
            f"""
            UPDATE {self.table_ref}
            SET description = %s
            WHERE id = %s
            """,
            (normalized_description, record_id),
        )
        return self.get_record_or_404(record_id)

    def generate_and_store_description(
        self,
        record_id: int,
        *,
        prompt: str,
    ) -> dict[str, Any]:
        conn = self.database.get_connection()
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SET @image_base64 = NULL")
            cursor.execute(
                f"""
                SELECT base64_payload
                INTO @image_base64
                FROM {self.table_ref}
                WHERE id = %s
                """,
                (record_id,),
            )
            cursor.execute("SELECT CHAR_LENGTH(@image_base64) AS payload_length")
            payload_row = cursor.fetchone()
            if not payload_row or not payload_row.get("payload_length"):
                raise NotFoundError("Image record not found.")

            result = self.generate_description_for_base64(
                cursor,
                base64_reference_sql="@image_base64",
                prompt=prompt,
            )
            cursor.execute(
                f"""
                UPDATE {self.table_ref}
                SET description = %s
                WHERE id = %s
                """,
                (result.text, record_id),
            )
            record = self.get_record(record_id)
            if not record:
                raise NotFoundError("Image record not found.")
            return record
        except AppError:
            raise
        except Exception as exc:
            raise BackendError(f"Description generation failed: {exc}") from exc
        finally:
            conn.close()

    def generate_image_insight_result(
        self,
        record_id: int,
        prompt: str,
    ) -> InsightGenerationResult:
        cleaned_prompt = prompt.strip()
        if not cleaned_prompt:
            raise ValidationError("Enter a prompt before generating an AI response.")

        conn = self.database.get_connection()
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SET @image_base64 = NULL")
            cursor.execute("SET @image_description = NULL")
            cursor.execute(
                f"""
                SELECT base64_payload, description
                INTO @image_base64, @image_description
                FROM {self.table_ref}
                WHERE id = %s
                """,
                (record_id,),
            )
            cursor.execute(
                """
                SELECT
                    CHAR_LENGTH(@image_base64) AS payload_length,
                    @image_description AS image_description
                """
            )
            payload_row = cursor.fetchone()
            if not payload_row or not payload_row.get("payload_length"):
                raise NotFoundError("Image record not found.")
            detected_language = self.detect_prompt_language(cursor, cleaned_prompt)
            description_context = normalize_description_text(
                payload_row.get("image_description")
            )
            if description_context:
                cursor.execute(
                    """
                    SELECT sys.ML_GENERATE(
                        %s,
                        JSON_OBJECT(
                            'task', 'generation',
                            'model_id', %s,
                            'language', %s,
                            'context', %s,
                            'image', @image_base64
                        )
                    ) AS response
                    """,
                    (
                        cleaned_prompt,
                        self.config.ai_model_id,
                        detected_language,
                        description_context,
                    ),
                )
            else:
                cursor.execute(
                    """
                    SELECT sys.ML_GENERATE(
                        %s,
                        JSON_OBJECT(
                            'task', 'generation',
                            'model_id', %s,
                            'language', %s,
                            'image', @image_base64
                        )
                    ) AS response
                    """,
                    (
                        cleaned_prompt,
                        self.config.ai_model_id,
                        detected_language,
                    ),
                )
            row = cursor.fetchone()
            if not row:
                raise BackendError("HeatWave did not return a response.")
            return InsightGenerationResult(
                text=parse_ml_generate_response(row.get("response")),
                detected_language=detected_language,
            )
        except AppError:
            raise
        except Exception as exc:
            raise BackendError(f"AI generation failed: {exc}") from exc
        finally:
            conn.close()

    def generate_image_insight(self, record_id: int, prompt: str) -> str:
        return self.generate_image_insight_result(record_id, prompt).text
