from __future__ import annotations

from typing import Any

from backend.config import AppConfig

DEFAULT_DATABASE = object()


class MySQLDatabase:
    def __init__(self, config: AppConfig) -> None:
        self.config = config

    def get_connection(self, *, database=DEFAULT_DATABASE):
        import mysql.connector  # type: ignore

        kwargs = {
            "host": self.config.db_host,
            "port": self.config.db_port,
            "user": self.config.db_user,
            "password": self.config.db_password,
            "autocommit": True,
        }
        target_database = self.config.db_schema if database is DEFAULT_DATABASE else database
        if target_database is not None:
            kwargs["database"] = target_database
        return mysql.connector.connect(**kwargs)

    def execute(self, sql: str, params: tuple = (), *, database=DEFAULT_DATABASE) -> None:
        conn = self.get_connection(database=database)
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute(sql, params)
        finally:
            conn.close()

    def fetch_all(
        self,
        sql: str,
        params: tuple = (),
        *,
        database=DEFAULT_DATABASE,
    ) -> list[dict[str, Any]]:
        conn = self.get_connection(database=database)
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute(sql, params)
            return list(cursor.fetchall())
        finally:
            conn.close()

    def fetch_one(
        self,
        sql: str,
        params: tuple = (),
        *,
        database=DEFAULT_DATABASE,
    ) -> dict[str, Any] | None:
        rows = self.fetch_all(sql, params, database=database)
        return rows[0] if rows else None

    def insert(
        self,
        sql: str,
        params: tuple = (),
        *,
        database=DEFAULT_DATABASE,
    ) -> int:
        conn = self.get_connection(database=database)
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute(sql, params)
            return int(cursor.lastrowid)
        finally:
            conn.close()
