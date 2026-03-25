from __future__ import annotations

import os
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = REPO_ROOT / ".env"
SQL_DIR = REPO_ROOT / "sql"


@dataclass(frozen=True)
class AppConfig:
    db_host: str
    db_port: int
    db_user: str
    db_password: str
    db_schema: str
    db_table: str
    ai_model_id: str
    ai_language: str


def load_dotenv_file(dotenv_path: Path = ENV_PATH) -> None:
    if not dotenv_path.exists():
        return

    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def get_env(name: str, default: str | None = None, *, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and (value is None or not str(value).strip()):
        raise RuntimeError(
            f"Missing required environment variable `{name}`. "
            "Copy `.env.example` to `.env` and fill in your HeatWave connection details."
        )
    return "" if value is None else str(value)


def quote_identifier(identifier: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", identifier):
        raise RuntimeError(
            f"Invalid SQL identifier `{identifier}`. Use only letters, numbers, and underscores."
        )
    return f"`{identifier}`"


@lru_cache(maxsize=1)
def get_config() -> AppConfig:
    load_dotenv_file()

    db_port_raw = get_env("DB_PORT", "3306")
    try:
        db_port = int(db_port_raw)
    except ValueError as exc:
        raise RuntimeError("`DB_PORT` must be an integer.") from exc

    return AppConfig(
        db_host=get_env("DB_HOST", required=True),
        db_port=db_port,
        db_user=get_env("DB_USER", required=True),
        db_password=get_env("DB_PASSWORD", required=True),
        db_schema=get_env("DB_SCHEMA", os.getenv("DB_NAME", "image_registry")),
        db_table=get_env("DB_TABLE", "image_assets"),
        ai_model_id=get_env("AI_MODEL_ID", "google.gemini-2.5-pro"),
        ai_language=get_env("AI_LANGUAGE", "en"),
    )


def clear_config_cache() -> None:
    get_config.cache_clear()
