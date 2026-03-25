from __future__ import annotations

from backend.bootstrap import SQLBootstrapper
from backend.config import AppConfig


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


def test_bootstrap_runs_sql_files_in_sorted_order(tmp_path) -> None:
    (tmp_path / "010_create_table.sql").write_text(
        "CREATE TABLE IF NOT EXISTS {{FULL_TABLE_NAME}} (id INT)",
        encoding="utf-8",
    )
    (tmp_path / "001_create_schema.sql").write_text(
        "CREATE SCHEMA IF NOT EXISTS {{SCHEMA_NAME}}",
        encoding="utf-8",
    )

    bootstrapper = SQLBootstrapper(make_config(), sql_dir=tmp_path)
    executed: list[tuple[str, object | None]] = []

    def record_execution(sql: str, params: tuple = (), *, database=None) -> None:
        executed.append((sql, database))

    bootstrapper.run(record_execution)

    assert executed == [
        ("CREATE SCHEMA IF NOT EXISTS `image_registry`", None),
        ("CREATE TABLE IF NOT EXISTS `image_registry`.`image_assets` (id INT)", None),
    ]
