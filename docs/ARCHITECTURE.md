# Architecture

celist.db ships as two native-feeling editions that share one product model and
one file format. This document explains how each is layered and, more
importantly, *why*.

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

## 2. macOS edition — SwiftUI + GRDB

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

## 3. Windows edition — Electron + sql.js

```
 renderer.js   Access-style ribbon UI, datasheet, designer, SQL editor
      │        (no Node access — contextIsolation + sandbox on)
 preload.js    contextBridge: `celistdb.*` — a small, explicit API surface
      │        (file dialogs, read/write file, platform info)
 main.js       Electron main process: window lifecycle + IPC handlers
      │
 sql.js        SQLite compiled to WebAssembly; database persisted as bytes
               written to the user's chosen .db file
```

The renderer holds the UI state (`S`) and talks to disk only through the
`celistdb` bridge. `contextIsolation` is on, `nodeIntegration` is off, and the
renderer's CSP allows only local scripts plus `wasm-unsafe-eval` for sql.js.

Because sql.js keeps the database in memory, every mutating action writes the
exported bytes back to the `.db` file — which is what makes the resulting file a
plain SQLite database that opens anywhere.

## 4. Shared conventions

| Concern | Convention |
|---|---|
| Database file | A single `.db` (or `.sqlite` / `.sqlite3`) file the user picks |
| Read-only objects | Views are listed and browseable but never edited |
| Blank cells | An empty cell means `NULL`, not an empty string |
| SQL generation | Always shown to the user before it runs (table designer) |
| Errors | Surfaced as human-readable messages next to the action |
| Sample data | "Create Sample Database" produces the same shop schema in both editions |

## 5. Where the code lives

| Path | Contents |
|---|---|
| `macos/Sources/CelistDBCore` | Engine-agnostic models + `DatabaseService` protocol |
| `macos/Sources/CelistDB` | macOS app: views, view models, app shell |
| `macos/Scripts` | Icon generation and `.app` packaging |
| `windows/src` | Electron main, preload, renderer, styles |
| `windows/src/gen_icon.py` | Windows `.ico` generation from the shared master |
| `docs/assets` | Shared logo artwork |
