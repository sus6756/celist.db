# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-10-18

First public release: **celist.db**, the database app for the rest of us.

### Added — macOS app (SwiftUI + GRDB)

- Visual table designer with column types, `PRIMARY KEY`, `NOT NULL`,
  `UNIQUE`, `AUTOINCREMENT`, `DEFAULT`, and foreign-key targets.
- Live `CREATE TABLE` SQL preview and type auto-suggestion from column names.
- Spreadsheet data grid with inline editing, add / duplicate / delete rows,
  filtering, and click-to-sort headers.
- Raw SQL editor with syntax highlighting, multi-statement execution, results
  grid, error surfacing, and per-database query history.
- Object browser sidebar with tables, views, and row counts.
- Sample shop database (customers, orders, order items) created in one click.
- CSV and JSON import; CSV and JSON export for the current table or query.
- Relationships viewer and one-click database backup (`VACUUM INTO`).

### Added — pandas companion (`tools/pycelist`)

- New read-only Python CLI, `celist`, that reads databases with pandas and
  writes styled Excel `.xlsx` workbooks.
- `celist info` — tables and views with row counts (`--json` supported).
- `celist export` — export a table, a read-only query, or a whole database
  (`--all-tables`), with `--sheet`, `--limit`, and a summary Index sheet.
- Workbook styling: brand-indigo bold headers, frozen header row, autofilter,
  fitted column widths, and number/date formats from the column dtypes.
- CSV-grade edge handling: `NULL` → blank, BLOBs → `0x…` hex, unicode
  identifiers and names, illegal/duplicate sheet names sanitised.
- Importable Python API (`connect`, `read_table`, `read_query`,
  `write_workbook`) sharing the same code path as the CLI.
- 21 unittest cases, including proof that mutating SQL is refused because every
  connection is opened with SQLite `mode=ro`.

### Added — project

- Product icon artwork, generated as `AppIcon.icns` from a single Python source.
- Architecture, roadmap, contributing, and changelog documentation.
- CI workflow that builds the Swift package and runs both test suites.

### Notes

- The build is not code-signed yet, so first launch requires the documented
  Gatekeeper bypass (see the README).

[1.0.0]: https://github.com/sus6756/celist.db/releases/tag/v1.0.0
