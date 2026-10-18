# Architecture

celist.db is a macOS app built on one product model and one file format. This
document explains how it is layered and, more importantly, *why*.

---

## 1. The product constraint that drives everything

The product promise is: **a beginner can create a database, design a table, and
edit data without ever seeing SQL — while a power user always has the SQL blade
available.**

Two consequences:

1. The interface must speak in *tables, columns, rows, and relationships*, and
   generate SQL as a side effect — never the other way around.
2. The storage engine must be swappable, because "a local SQLite file" is the
   right default for beginners but not the only thing people will ask for. That
   is why the data layer is a protocol, not a concrete class.

## 2. The app — SwiftUI + GRDB

```
 SwiftUI Views              Views/, AccessTheme.swift, RibbonView.swift
        │  (environment objects)
 ViewModels                 ViewModels/ (AppState, TableViewModel,
        │                    TableDesignerViewModel, QueryViewModel)
 Services                   CelistDBCore/Services/DatabaseService.swift
        │                    (protocol) ──▶ SQLiteService (GRDB)
 Models                     CelistDBCore/Models (SchemaModels, DesignerModels,
                             QueryModels)
```

- **`CelistDBCore`** is a pure Swift library with no SwiftUI dependency. It owns
  the models and the `DatabaseService` protocol, and it is the only thing the
  tests touch.
- **`SQLiteService`** implements `DatabaseService` with
  [GRDB](https://github.com/groue/GRDB.swift) on top of the SQLite copy that
  already ships with macOS. That means zero bundled database engine and full
  offline behavior from day one.
- **`CelistDB`** is the executable target: the app shell, ribbon, sidebar,
  datasheet grid, table designer, and SQL editor.
- **Undo/redo** and wizard state live at the view-model level, so they will
  behave identically once other engines are added.

### Why native and not Electron/Tauri on macOS?

- SQLite is in the OS; the local engine costs no dependency weight.
- A spreadsheet grid over thousands of rows, and instant table/window
  interactions, are exactly what non-native shells struggle with.
- Real menu commands, trackpad gestures, and App Store distribution come for
  free.

### Adding another engine (v2)

Implement the `DatabaseService` protocol — `listObjects()`, `schema(for:)`,
`fetchRows(in:state:)`, `updateCell(_:column:rowID:in:)`, `runSQL(_:)`, and so
on — and hand it to `AppState` instead of `SQLiteService`. No view changes.

## 3. Shared conventions

| Concern | Convention |
|---|---|
| Database file | A single `.db` (or `.sqlite` / `.sqlite3`) file the user picks |
| Read-only objects | Views are listed and browseable but never edited |
| Blank cells | An empty cell means `NULL`, not an empty string |
| SQL generation | Always shown to the user before it runs (table designer) |
| Errors | Surfaced as human-readable messages next to the action |
| Sample data | "Create Sample Database" produces a ready-made shop schema with rows |

## 4. Where the code lives

| Path | Contents |
|---|---|
| `macos/Sources/CelistDBCore` | Engine-agnostic models + `DatabaseService` protocol |
| `macos/Sources/CelistDB` | App: views, view models, app shell |
| `macos/Scripts` | Icon generation and `.app` packaging |
| `tools/pycelist` | Read-only pandas CLI + importable API for styled Excel export |
| `docs/assets` | Logo artwork |

## 5. The optional pandas companion

`tools/pycelist` is deliberately *outside* the app:

- Bundling pandas would add ~60 MB and a whole Python runtime to the macOS
  package, for a feature most users open once a month.
- A CLI over the same `.db` files works standalone, in scripts, in CI, and in
  notebooks — no app running required.
- The app can shell out to it later (`celist export …`) without changing its
  architecture; the command only needs `python3` on `PATH`, and if it is
  missing the app simply does not offer the extra commands.

It shares the product's data contract rather than its code: it reads the same
SQLite files, treats an empty cell as `NULL`, and refuses to write to the
database at all (SQLite `mode=ro`), so the "your file is yours" guarantee holds
even for the analytics path.

```
  celist.db app ──writes──▶ shop.db ◀──read-only── celist (pandas CLI)
                              │                        │
                              │                        ▼
                     any SQLite tool            styled .xlsx / (later:
                                                profiles, pivots, charts)
```
