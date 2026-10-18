"""pandas-powered export utilities for celist.db databases.

The package is intentionally read-only: every connection it opens uses SQLite's
``mode=ro`` URI mode, so a celist command can never modify the database it is
asked to export.

    >>> from celistdb import read_table, write_workbook
    >>> df = read_table("shop.db", "orders")          # doctest: +SKIP
    >>> write_workbook({"orders": df}, "orders.xlsx")  # doctest: +SKIP
"""

from .db import (
    CelistDBError,
    ObjectInfo,
    connect,
    list_objects,
    quote_ident,
    read_query,
    read_table,
    row_count,
)
from .excel import sanitize_sheet_name, unique_sheet_name, write_workbook

__version__ = "1.0.0"

__all__ = [
    "CelistDBError",
    "ObjectInfo",
    "connect",
    "list_objects",
    "quote_ident",
    "read_query",
    "read_table",
    "row_count",
    "sanitize_sheet_name",
    "unique_sheet_name",
    "write_workbook",
    "__version__",
]
