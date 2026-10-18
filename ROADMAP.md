# celist.db — Product Roadmap

One database app for everyone. Powerful under the hood, dead simple to use.

## Architecture decision

**Native SwiftUI + GRDB (SQLite), MVVM, protocol-driven** on macOS, with an
**Electron + sql.js** edition for Windows that mirrors the same product model.
See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full rationale.

Why not a single cross-platform runtime (Electron/Tauri) for both?

- **SQLite/FTS is built into macOS** — the local storage engine costs us zero
  dependency weight and works offline from day one.
- **Native performance & feel**: a spreadsheet grid over thousands of rows, and
  instant window/table interactions, are exactly what non-native apps struggle
  with. Native also gets us real menu commands, trackpad gestures, and
  App-Store distribution for free.
- **Multiple DB engines later**: we do *not* couple the app to SQLite. All data
  access goes through the `DatabaseService` protocol. SQLite is today's
  implementation; MySQL/PostgreSQL/SQL Server are added later as v2
  implementations of the same protocol.

Layering:

```
SwiftUI Views
   │  (ObservableObject view models)
Services: DatabaseService (protocol)
   │
   ├─ SQLiteService (GRDB)           — MVP, ships now
   ├─ MySQLService  (v2)
   ├─ PostgreSQLService (v2)
   └─ SQLServerService (v2)
```

Undo/redo is planned at the view-model level (command stacks), so it will work
uniformly regardless of engine. Wizards & empty states live in the view layer.

---

## MVP (shipping) — "Local SQLite for the rest of us"

Goal: a beginner can create a database, design a table, and edit data without
ever seeing SQL — while a power user can still use the SQL tab.

- [x] Create / open / switch SQLite databases (`File > New`, `File > Open`)
- [x] Visual table designer (`Data / Design / SQL` tabs per table)
  - add/remove columns, pick data types from curated list
  - PK / NOT NULL / UNIQUE / AUTOINCREMENT / DEFAULT / FK target
  - live SQL preview of the `CREATE TABLE` that will run
  - type auto-suggestion from column names (e.g. `email → TEXT`, `qty → INT`)
  - sample-database onboarding (Customers/Orders/OrderItems with rows)
- [x] Spreadsheet data grid
  - inline cell editing committed to DB on change
  - add / duplicate / delete rows, filter box, sort by clicking headers
  - column types honored: integers/decimals parse, empty = NULL
- [x] Raw SQL tab with syntax highlighting, multi-statement run, results grid,
  error surfacing, and persistent query history
- [x] Sidebar object browser (tables + views), row counts, schema header
- [x] External Data tab: CSV import, JSON import, and CSV / JSON export, scoped
  to the current table or query result
- [x] Database Tools tab: Relationships viewer (foreign-key list) + database
  backup (`VACUUM INTO` on macOS, byte-for-byte export on Windows)
- [x] Windows edition: Electron + sql.js, same ribbon-driven workflow

### Companion tooling

- [x] `tools/pycelist` — read-only pandas CLI (`celist`) for styled Excel
  `.xlsx` export: single sheets, whole-database workbooks with an Index sheet,
  dtype-aware number/date formats, frozen headers, autofilter
- [ ] Profiling reports (dtypes, nulls, uniques, summary stats)
- [ ] Smarter CSV/JSON import (dtype inference, delimiter/header detection)
- [ ] Pivot / group-by / merge without SQL, written back as a table or view
- [ ] Charts from query results
- [ ] Parquet / Feather I/O

Not in MVP (deliberately): remote connections, drag-to-link ER diagram, forms,
reports, permissions. Those are staged below so each phase lands coherently.

## v1 — Daily-driver productivity

- [x] Native Excel (`.xlsx`) export — ships today as the read-only
  [`tools/pycelist`](tools/pycelist) companion CLI: styled, multi-sheet
  workbooks with a summary Index sheet (see below)
- Visual query builder (point-and-click joins/filters/grouping) with live SQL
- Richer import mapping (choose delimiter, header row, column types)
- Saved queries & saved views
- Relationships ER diagram: drag-to-link foreign keys on top of the MVP viewer
- Undo/redo throughout (command stack) + guided wizards with tooltips
- Table alterations (rename, add/drop columns, constraints) via schema migrate
- Enhanced cell editors: FK dropdowns, date pickers, checkbox booleans

## v2 — Connected & serious

- Remote engines behind `DatabaseService`: MySQL, PostgreSQL, SQL Server
- Visual connection manager with saved/reusable profiles (keychain-backed)
- Forms builder (drag-and-drop, bound to tables/queries/views)
- Reports designer with grouping, totals, PDF export
- Backup/restore (backup ships in MVP; restore + schema export/import and DB
  diagnostics are the remaining pieces)
- Basic automation/triggers ("when a row is added, do X") — no-code macros
- User/role permissions for remote databases

---

## How to build & run

**macOS**

```bash
cd macos
swift run
```

Or open `macos/` in Xcode (Swift Package) and Run. Requires macOS 14+.

**Windows**

```bash
cd windows
npm install
npm start
```
