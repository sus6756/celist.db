"""The ``celist`` command line interface.

    celist info shop.db
    celist export shop.db --table orders -o orders.xlsx
    celist export shop.db --query "SELECT * FROM orders" --sheet "Recent orders"
    celist export shop.db --all-tables -o shop.xlsx

Every command opens the database read-only.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from pathlib import Path
from typing import Optional, Sequence

import pandas as pd

from . import __version__
from .db import CelistDBError, connect, list_objects, read_query, read_table, row_count
from .excel import write_workbook

PROG = "celist"

# Exported formats. Today only Excel; new formats plug in here.
FORMATS = ("xlsx",)
DEFAULT_FORMAT = "xlsx"


def _path_stem(path: Path) -> str:
    return path.stem or "database"


def _safe_slug(text: str, fallback: str = "export") -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", str(text)).strip("-._")
    return slug or fallback


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Export celist.db (SQLite) data with pandas.",
        epilog="Databases are always opened read-only.",
    )
    parser.add_argument("--version", action="version", version=f"{PROG} {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    info = sub.add_parser("info", help="list tables and views with row counts")
    info.add_argument("database", help="path to a .db / .sqlite file")
    info.add_argument("--views-only", action="store_true", help="only list views")
    info.add_argument("--json", action="store_true", help="machine-readable output")

    export = sub.add_parser("export", help="export tables or a query to a workbook")
    export.add_argument("database", help="path to a .db / .sqlite file")
    source = export.add_mutually_exclusive_group(required=True)
    source.add_argument("--table", "-t", help="table or view to export")
    source.add_argument("--query", "-q", help="read-only SQL to export")
    source.add_argument(
        "--all-tables", action="store_true", help="export every table to its own sheet"
    )
    export.add_argument("--include-views", action="store_true",
                       help="with --all-tables, also export views")
    export.add_argument("--output", "-o", help="output path (default: beside the database)")
    export.add_argument("--sheet", "-s", help="sheet name (single source only)")
    export.add_argument("--limit", "-n", type=int, help="export at most N rows")
    export.add_argument("--format", "-f", choices=FORMATS, default=DEFAULT_FORMAT,
                        help=f"output format (default: {DEFAULT_FORMAT})")
    export.add_argument("--no-index", action="store_true",
                        help="with --all-tables, skip the summary Index sheet")
    return parser


# ------------------------------------------------------------------------
# commands
# ------------------------------------------------------------------------
def cmd_info(args: argparse.Namespace) -> int:
    types = ("view",) if args.views_only else ("table", "view")
    with connect(args.database) as conn:
        objects = list_objects(conn, types)
        counted = [(obj.name, obj.type, row_count(conn, obj.name)) for obj in objects]

    if args.json:
        import json

        print(
            json.dumps(
                {
                    "database": str(Path(args.database).expanduser()),
                    "objects": [
                        {"name": name, "type": kind, "rows": rows}
                        for name, kind, rows in counted
                    ],
                },
                indent=2,
            )
        )
        return 0

    print(f"Database: {Path(args.database).expanduser()}")
    if not counted:
        print("  (no tables or views)")
        return 0
    width = max(len(name) for name, _, _ in counted)
    for kind in ("table", "view"):
        group = [(n, r) for n, k, r in counted if k == kind]
        if not group:
            continue
        print(f"  {kind}s ({len(group)})")
        for name, rows in group:
            print(f"    {name.ljust(width)}  {rows:>10,} rows")
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    db_path = Path(args.database).expanduser()
    sheets: dict[str, pd.DataFrame] = {}
    label = "export"
    index_sheet = False

    with connect(db_path) as conn:
        if args.all_tables:
            types = ("table", "view") if args.include_views else ("table",)
            objects = list_objects(conn, types)
            if not objects:
                raise CelistDBError("no tables found in this database")
            for obj in objects:
                sheets[obj.name] = read_table(db_path, obj.name, limit=args.limit, conn=conn)
            label = "export"
            index_sheet = len(sheets) > 1
        elif args.query:
            sheets[args.sheet or "Query"] = read_query(
                db_path, args.query, limit=args.limit, conn=conn
            )
            label = "query"
        else:
            sheets[args.sheet or args.table] = read_table(
                db_path, args.table, limit=args.limit, conn=conn
            )
            label = _safe_slug(args.table)

    if args.no_index:
        index_sheet = False

    output = Path(args.output).expanduser() if args.output else (
        db_path.parent / f"{_path_stem(db_path)}-{_safe_slug(label)}.{args.format}"
    )

    path = write_workbook(sheets, output, index_sheet=index_sheet)
    total_rows = sum(len(df) for df in sheets.values())
    sheet_word = "sheet" if len(sheets) == 1 else "sheets"
    print(
        f"Wrote {path} — {len(sheets)} {sheet_word}, {total_rows:,} rows"
        + (" (+ Index)" if index_sheet else "")
    )
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    handlers = {"info": cmd_info, "export": cmd_export}
    try:
        return handlers[args.command](args)
    except CelistDBError as exc:
        print(f"{PROG}: error: {exc}", file=sys.stderr)
        return 1
    except sqlite3.Error as exc:
        print(f"{PROG}: database error: {exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError) as exc:
        print(f"{PROG}: error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
