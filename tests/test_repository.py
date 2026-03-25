from __future__ import annotations

from collections import deque

from backend.config import AppConfig
from backend.repository import MySQLImageRepository


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


class FakeBootstrapper:
    def __init__(self) -> None:
        self.run_calls = 0

    def run(self, executor) -> None:
        self.run_calls += 1


class RecordingDatabase:
    def __init__(self) -> None:
        self.fetch_all_calls: list[tuple[str, tuple, object]] = []
        self.fetch_one_calls: list[tuple[str, tuple, object]] = []
        self.fetch_one_responses: deque[dict[str, object] | None] = deque()
        self.execute_calls: list[tuple[str, tuple, object]] = []
        self.connection = None

    def fetch_all(self, sql: str, params: tuple = (), *, database=None):
        self.fetch_all_calls.append((sql, params, database))
        return []

    def fetch_one(self, sql: str, params: tuple = (), *, database=None):
        self.fetch_one_calls.append((sql, params, database))
        if not self.fetch_one_responses:
            raise AssertionError("fetch_one response was not configured for this test")
        return self.fetch_one_responses.popleft()

    def insert(self, sql: str, params: tuple = (), *, database=None):
        raise AssertionError("insert should not be called in this test")

    def execute(self, sql: str, params: tuple = (), *, database=None) -> None:
        self.execute_calls.append((sql, params, database))

    def get_connection(self):
        assert self.connection is not None
        return self.connection


class FakeCursor:
    def __init__(self, responses: list[dict[str, object] | None]) -> None:
        self.responses = deque(responses)
        self.executed: list[tuple[str, tuple]] = []

    def execute(self, sql: str, params: tuple = ()) -> None:
        self.executed.append((sql, params))

    def fetchone(self):
        if not self.responses:
            return None
        return self.responses.popleft()


class FakeConnection:
    def __init__(self, cursor: FakeCursor) -> None:
        self._cursor = cursor
        self.closed = False

    def cursor(self, dictionary: bool = True) -> FakeCursor:
        assert dictionary is True
        return self._cursor

    def close(self) -> None:
        self.closed = True


def test_list_records_uses_desc_order_and_search_filter() -> None:
    database = RecordingDatabase()
    repository = MySQLImageRepository(
        make_config(),
        database=database,
        bootstrapper=FakeBootstrapper(),
    )

    repository.list_records("hood")

    assert len(database.fetch_all_calls) == 1
    sql, params, _ = database.fetch_all_calls[0]
    assert "WHERE image_name LIKE %s" in sql
    assert "ORDER BY created_at DESC, id DESC" in sql
    assert params == ("%hood%",)


def test_ensure_schema_and_table_adds_description_column_when_missing() -> None:
    bootstrapper = FakeBootstrapper()
    database = RecordingDatabase()
    database.fetch_one_responses.append({"column_count": 0})
    repository = MySQLImageRepository(
        make_config(),
        database=database,
        bootstrapper=bootstrapper,
    )

    repository.ensure_schema_and_table()

    assert bootstrapper.run_calls == 1
    assert len(database.fetch_one_calls) == 1
    assert len(database.execute_calls) == 1
    sql, params, database_name = database.execute_calls[0]
    assert "ALTER TABLE `image_registry`.`image_assets`" in sql
    assert "ADD COLUMN description TEXT NULL" in sql
    assert "AFTER base64_payload" in sql
    assert params == (
        "User-provided or AI-generated image description used as prompt context",
    )
    assert database_name is None


def test_generate_upload_description_parses_json_response() -> None:
    database = RecordingDatabase()
    cursor = FakeCursor(
        [
            {"response": '{"text":"en"}'},
            {"response": '{"text":"Blue truck parked in a grassy field under a bright sky."}'},
        ]
    )
    database.connection = FakeConnection(cursor)
    repository = MySQLImageRepository(
        make_config(),
        database=database,
        bootstrapper=FakeBootstrapper(),
    )

    result = repository.generate_upload_description(
        base64_payload="ZmFrZS1iYXNlNjQ=",
        prompt="Describe it for cataloging",
    )

    assert result.text == "Blue truck parked in a grassy field under a bright sky."
    assert result.detected_language == "en"
    assert cursor.executed[0][1] == ("ZmFrZS1iYXNlNjQ=",)
    assert "ISO 639-1 two-letter code" in cursor.executed[1][1][0]
    assert cursor.executed[2][1] == (
        "Generate a reusable description of this image for future AI context. "
        "Follow the user's guidance when it is consistent with the visible content. "
        "Keep the result grounded in the image and write a standalone description.\n\n"
        "User guidance:\n"
        "Describe it for cataloging",
        "model-id",
        "en",
    )


def test_generate_image_insight_uses_detected_language_and_context_and_parses_json_response() -> None:
    database = RecordingDatabase()
    cursor = FakeCursor(
        [
            {
                "payload_length": 120,
                "image_description": "Reusable description of the selected image.",
            },
            {"response": '{"text":"es"}'},
            {"response": '{"text":"Detected a blue truck."}'},
        ]
    )
    database.connection = FakeConnection(cursor)
    repository = MySQLImageRepository(
        make_config(),
        database=database,
        bootstrapper=FakeBootstrapper(),
    )

    response = repository.generate_image_insight_result(7, "Describe this image")

    assert response.text == "Detected a blue truck."
    assert response.detected_language == "es"
    assert cursor.executed[2][1] == (7,)
    assert "ISO 639-1 two-letter code" in cursor.executed[4][1][0]
    assert "Describe this image" in cursor.executed[4][1][0]
    assert cursor.executed[4][1][1:] == ("model-id", "en")
    assert "'context', %s" in cursor.executed[5][0]
    assert cursor.executed[5][1] == (
        "Describe this image",
        "model-id",
        "es",
        "Reusable description of the selected image.",
    )


def test_generate_image_insight_falls_back_to_configured_language_without_context() -> None:
    database = RecordingDatabase()
    cursor = FakeCursor(
        [
            {"payload_length": 64, "image_description": "   "},
            {"response": "spanish"},
            {"response": "Raw model response"},
        ]
    )
    database.connection = FakeConnection(cursor)
    repository = MySQLImageRepository(
        make_config(),
        database=database,
        bootstrapper=FakeBootstrapper(),
    )

    response = repository.generate_image_insight_result(9, "Summarize")

    assert response.text == "Raw model response"
    assert response.detected_language == "en"
    assert "'context', %s" not in cursor.executed[5][0]
    assert cursor.executed[5][1] == ("Summarize", "model-id", "en")
