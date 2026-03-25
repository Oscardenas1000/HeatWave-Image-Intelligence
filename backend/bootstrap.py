from __future__ import annotations

from pathlib import Path
from typing import Protocol

from backend.config import AppConfig, SQL_DIR, quote_identifier


class BootstrapExecutor(Protocol):
    def __call__(self, sql: str, params: tuple = (), *, database=...) -> None: ...


class SQLBootstrapper:
    def __init__(self, config: AppConfig, sql_dir: Path = SQL_DIR) -> None:
        self.config = config
        self.sql_dir = sql_dir

    @property
    def table_ref(self) -> str:
        return (
            f"{quote_identifier(self.config.db_schema)}."
            f"{quote_identifier(self.config.db_table)}"
        )

    def render_sql_template(self, sql_text: str) -> str:
        rendered = sql_text
        replacements = {
            "{{SCHEMA_NAME}}": quote_identifier(self.config.db_schema),
            "{{TABLE_NAME}}": quote_identifier(self.config.db_table),
            "{{FULL_TABLE_NAME}}": self.table_ref,
        }
        for placeholder, value in replacements.items():
            rendered = rendered.replace(placeholder, value)
        return rendered.strip()

    def get_bootstrap_sql_files(self) -> list[Path]:
        sql_files = sorted(self.sql_dir.glob("*.sql"))
        if not sql_files:
            raise RuntimeError(f"No bootstrap SQL files were found in `{self.sql_dir}`.")
        return sql_files

    def run(self, executor: BootstrapExecutor) -> None:
        for sql_file in self.get_bootstrap_sql_files():
            executor(
                self.render_sql_template(sql_file.read_text(encoding="utf-8")),
                database=None,
            )
