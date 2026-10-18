"""Read-only SQLite access, expressed as pandas DataFrames."""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence, Union

import pandas as pd

PathLike = Union[str, Path]


class CelistDBError(RuntimeError):
    """A user-facing failure: missing file, missing table, bad arguments."""


class _ClosingConnection(sqlite3.Connection):
    """A connection that really closes on ``with`` exit.

    ``sqlite3.Connection`` is a transaction context manager, not a resource
    one: leaving the block commits but leaves the file handle open.
    """

    def __exit__(self, exc_type, exc_value, traceback):
        try:
            return super().__exit__(exc_type, exc_value, traceback)
        finally:
            self.close()


def connect(path: PathLike) -> sqlite3.Connection:
    """Open *path* read-only.

    Read-only mode is deliberate: exporting, profiling, and charting never need
    to write, and this guarantees the tool cannot corrupt a live database.
    """
    db_path = Path(path).expanduser()
    if not db_path.exists():
        raise CelistDBError(f"database not found: {db_path}")
    if db_path.is_dir():
        raise CelistDBError(f"not a database file (is a directory): {db_path}")
    uri = f"file:{db_path.resolve().as_posix()}?mode=ro"
    return sqlite3.connect(uri, uri=True, factory=_ClosingConnection)


def quote_ident(name: str) -> str:
    """Quote an SQLite identifier, escaping embedded quotes."""
    return '"' + str(name).replace('"', '""') + '"'


@dataclass(frozen=True)
class ObjectInfo:
    """A table or view in the database."""

    name: str
    type: str
    rows: Optional[int] = None


def list_objects(
    conn: sqlite3.Connection, types: Sequence[str] = ("table", "view")
) -> list[ObjectInfo]:
    """List tables and views, tables first, each alphabetically."""
    if not types:
        return []
    placeholders = ", ".join("?" for _ in types)
    sql = (
        f"SELECT name, type FROM sqlite_master WHERE type IN ({placeholders}) "
        "AND name NOT LIKE 'sqlite_%' "
        "ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name COLLATE NOCASE"
    )
    rows = conn.execute(sql, tuple(types)).fetchall()
    return [ObjectInfo(name=str(n), type=str(t)) for n, t in rows]


def row_count(conn: sqlite3.Connection, name: str) -> int:
    """Row count for a table or view."""
    try:
        return int(conn.execute(f"SELECT COUNT(*) FROM {quote_ident(name)}").fetchone()[0])
    except sqlite3.Error as exc:  # pragma: no cover - defensive
        raise CelistDBError(f"cannot count rows in {name!r}: {exc}") from exc


def read_table(
    source: PathLike,
    table: str,
    *,
    limit: Optional[int] = None,
    conn: Optional[sqlite3.Connection] = None,
) -> pd.DataFrame:
    """Read *table* (or a view) into a DataFrame.

    ``source`` may be a database path or an already-open connection.
    """
    return _read(source, conn, f"SELECT * FROM {quote_ident(table)}", limit)


def read_query(
    source: PathLike,
    sql: str,
    *,
    limit: Optional[int] = None,
    conn: Optional[sqlite3.Connection] = None,
) -> pd.DataFrame:
    """Run a read-only SQL query into a DataFrame."""
    return _read(source, conn, sql, limit)


def _read(source, conn, sql: str, limit: Optional[int]) -> pd.DataFrame:
    if limit is not None:
        if limit <= 0:
            raise CelistDBError("--limit must be a positive integer")
        sql = f"SELECT * FROM (\n{sql.rstrip().rstrip(';')}\n) LIMIT {int(limit)}"
    try:
        if conn is None:
            with connect(source) as owned:
                return pd.read_sql_query(sql, owned)
        return pd.read_sql_query(sql, conn)
    except pd.errors.DatabaseError as exc:
        # pandas wraps sqlite3 errors; surface a clean message instead.
        raise CelistDBError(str(exc)) from exc


def object_infos(conn: sqlite3.Connection, types: Sequence[str] = ("table", "view")) -> list[ObjectInfo]:
    """List objects together with their row counts."""
    return [
        ObjectInfo(name=obj.name, type=obj.type, rows=row_count(conn, obj.name))
        for obj in list_objects(conn, types)
    ]
