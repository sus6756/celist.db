"""Tests for the pandas export layer. Run with: python3 -m unittest discover -s tests"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from celistdb import (  # noqa: E402
    CelistDBError,
    connect,
    list_objects,
    read_query,
    read_table,
    sanitize_sheet_name,
    unique_sheet_name,
    write_workbook,
)
from celistdb.excel import prepare_dataframe  # noqa: E402

PACKAGE_ROOT = Path(__file__).resolve().parent.parent


def build_sample_db(path: Path) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE orders (
            id INTEGER PRIMARY KEY,
            customer TEXT NOT NULL,
            amount REAL,
            placed_at TEXT,
            receipt BLOB,
            note TEXT
        );
        CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
        CREATE VIEW big_orders AS SELECT * FROM orders WHERE amount > 100;
        """
    )
    conn.executemany(
        "INSERT INTO orders VALUES (?, ?, ?, ?, ?, ?)",
        [
            (1, "Ada Lovelace", 128.5, "2026-01-02", b"\x00\x01\xff", None),
            (2, "Grace Hopper", 42.0, "2026-01-03", None, "call back"),
            (3, "Æthelred ✓", 310.75, "2026-02-14", None, None),
            (4, "Ada Lovelace", 128.5, "2026-01-02", b"\x10", "duplicate row"),
        ],
    )
    conn.execute("INSERT INTO customers VALUES (1, 'Ada Lovelace')")
    conn.commit()
    conn.close()


class ReadOnlyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "shop.db"
        build_sample_db(self.db)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_lists_tables_and_views(self) -> None:
        with connect(self.db) as conn:
            objects = list_objects(conn)
        self.assertEqual(
            [(o.name, o.type) for o in objects],
            [("customers", "table"), ("orders", "table"), ("big_orders", "view")],
        )

    def test_reads_table_and_view(self) -> None:
        with connect(self.db) as conn:
            orders = read_table(self.db, "orders", conn=conn)
            big = read_table(self.db, "big_orders", conn=conn)
        self.assertEqual(list(orders.columns), ["id", "customer", "amount", "placed_at", "receipt", "note"])
        self.assertEqual(len(orders), 4)
        self.assertEqual(len(big), 3)
        self.assertTrue(pd.isna(orders.loc[0, "note"]))

    def test_limit_applies(self) -> None:
        with connect(self.db) as conn:
            frame = read_table(self.db, "orders", limit=2, conn=conn)
        self.assertEqual(len(frame), 2)

    def test_write_is_refused(self) -> None:
        """The read-only guarantee: mutating SQL cannot run through this tool."""
        with self.assertRaises(CelistDBError) as ctx:
            read_query(self.db, "DROP TABLE orders")
        self.assertIn("readonly", str(ctx.exception).lower())
        with connect(self.db) as conn:
            self.assertEqual(len(read_table(self.db, "orders", conn=conn)), 4)

    def test_missing_database_is_a_clear_error(self) -> None:
        with self.assertRaises(CelistDBError) as ctx:
            connect(Path(self.tmp.name) / "nope.db")
        self.assertIn("database not found", str(ctx.exception))

    def test_quotes_awkward_identifiers(self) -> None:
        conn = sqlite3.connect(self.db)
        conn.execute('CREATE TABLE "weird ""name""" (a INTEGER)')
        conn.execute('INSERT INTO "weird ""name""" VALUES (7)')
        conn.commit()
        conn.close()
        with connect(self.db) as ro:
            frame = read_table(self.db, 'weird "name"', conn=ro)
        self.assertEqual(frame.iloc[0, 0], 7)


class ExcelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "shop.db"
        build_sample_db(self.db)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_single_sheet_round_trip(self) -> None:
        with connect(self.db) as conn:
            frame = read_table(self.db, "orders", conn=conn)
        target = Path(self.tmp.name) / "orders.xlsx"
        write_workbook({"orders": frame}, target)

        self.assertTrue(target.exists())
        back = pd.read_excel(target, sheet_name="orders")
        self.assertEqual(list(back.columns), list(frame.columns))
        self.assertEqual(len(back), 4)
        self.assertEqual(back.loc[0, "customer"], "Ada Lovelace")
        self.assertAlmostEqual(float(back.loc[0, "amount"]), 128.5)
        self.assertTrue(pd.isna(back.loc[0, "note"]))

    def test_blobs_become_hex(self) -> None:
        blob = prepare_dataframe(pd.DataFrame({"receipt": [b"\x00\x01\xff"]}))
        self.assertEqual(blob.loc[0, "receipt"], "0x0001ff")

    def test_header_is_styled_and_frozen(self) -> None:
        frame = pd.DataFrame({"amount": [1.5, 2.25], "name": ["a", "b"]})
        target = Path(self.tmp.name) / "styled.xlsx"
        write_workbook({"data": frame}, target)

        from openpyxl import load_workbook

        sheet = load_workbook(target)["data"]
        header = sheet["A1"]
        self.assertTrue(header.font.bold)
        self.assertEqual(header.fill.fgColor.rgb, "00261A54")
        self.assertEqual(sheet.freeze_panes, "A2")
        self.assertEqual(sheet.auto_filter.ref, "A1:B3")
        self.assertEqual(sheet["A2"].number_format, "#,##0.00")
        self.assertGreaterEqual(sheet.column_dimensions["B"].width, 9)

    def test_multi_sheet_export_has_index(self) -> None:
        with connect(self.db) as conn:
            sheets = {
                name: read_table(self.db, name, conn=conn)
                for name in ("orders", "customers")
            }
        target = Path(self.tmp.name) / "all.xlsx"
        write_workbook(sheets, target, index_sheet=True)

        book = pd.read_excel(target, sheet_name=None)
        self.assertEqual(list(book.keys()), ["Index", "orders", "customers"])
        self.assertEqual(book["Index"].loc[0, "Rows"], 4)

    def test_sheet_names_are_sanitised_and_unique(self) -> None:
        self.assertEqual(sanitize_sheet_name("a/b:c*d"), "a_b_c_d")
        self.assertEqual(len(sanitize_sheet_name("x" * 80)), 31)
        taken: set[str] = set()
        self.assertEqual(unique_sheet_name("Orders", taken), "Orders")
        self.assertEqual(unique_sheet_name("orders", taken), "orders (2)")

    def test_empty_frame_still_writes(self) -> None:
        target = Path(self.tmp.name) / "empty.xlsx"
        write_workbook({"nothing": pd.DataFrame()}, target)
        frame = pd.read_excel(target, sheet_name="nothing")
        self.assertEqual(list(frame.columns), ["note"])


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "shop.db"
        build_sample_db(self.db)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-m", "celistdb", *args],
            cwd=PACKAGE_ROOT,
            capture_output=True,
            text=True,
        )

    def test_info_lists_tables_with_counts(self) -> None:
        result = self.run_cli("info", str(self.db))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tables (2)", result.stdout)
        self.assertIn("orders", result.stdout)
        self.assertIn("views (1)", result.stdout)
        self.assertIn("4 rows", result.stdout)

    def test_info_json(self) -> None:
        import json

        result = self.run_cli("info", str(self.db), "--json")
        payload = json.loads(result.stdout)
        names = [o["name"] for o in payload["objects"]]
        self.assertIn("orders", names)

    def test_export_table_default_output_name(self) -> None:
        result = self.run_cli("export", str(self.db), "--table", "orders")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = self.db.parent / "shop-orders.xlsx"
        self.assertTrue(expected.exists())
        self.assertIn(str(expected), result.stdout)
        self.assertEqual(len(pd.read_excel(expected, sheet_name="orders")), 4)

    def test_export_query_with_sheet_name(self) -> None:
        target = Path(self.tmp.name) / "recent.xlsx"
        result = self.run_cli(
            "export", str(self.db),
            "--query", "SELECT id, customer FROM orders WHERE amount > 100",
            "--sheet", "Recent orders",
            "-o", str(target),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        frame = pd.read_excel(target, sheet_name="Recent orders")
        self.assertEqual(list(frame.columns), ["id", "customer"])
        self.assertEqual(len(frame), 3)

    def test_export_all_tables_creates_index(self) -> None:
        target = Path(self.tmp.name) / "everything.xlsx"
        result = self.run_cli("export", str(self.db), "--all-tables", "-o", str(target))
        self.assertEqual(result.returncode, 0, result.stderr)
        book = pd.read_excel(target, sheet_name=None)
        self.assertEqual(list(book.keys()), ["Index", "customers", "orders"])
        self.assertIn("(+ Index)", result.stdout)

    def test_export_respects_limit(self) -> None:
        target = Path(self.tmp.name) / "two.xlsx"
        result = self.run_cli("export", str(self.db), "--table", "orders", "-n", "2",
                              "-o", str(target))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(pd.read_excel(target, sheet_name="orders")), 2)

    def test_cli_refuses_to_write_to_the_database(self) -> None:
        result = self.run_cli("export", str(self.db), "--query", "DELETE FROM orders",
                              "-o", str(Path(self.tmp.name) / "x.xlsx"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("readonly", result.stderr.lower())
        with connect(self.db) as conn:
            self.assertEqual(len(read_table(self.db, "orders", conn=conn)), 4)

    def test_missing_table_reports_cleanly(self) -> None:
        result = self.run_cli("export", str(self.db), "--table", "ghosts")
        self.assertEqual(result.returncode, 1)
        self.assertIn("celist: error:", result.stderr)

    def test_version(self) -> None:
        result = self.run_cli("--version")
        self.assertEqual(result.returncode, 0)
        self.assertIn("celist 1.0.0", result.stdout)


if __name__ == "__main__":
    unittest.main()
