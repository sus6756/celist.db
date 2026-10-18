# celist.db — macOS edition

Native SwiftUI app (GRDB over system SQLite). This folder is the Swift package;
the product overview, features, and install instructions live in the
[repository README](../README.md).

## Run

```bash
swift run                # build & launch
swift build -c release   # optimized binary
./Scripts/make_app.sh    # dist/celist.db.app + dist/celist.db.zip
swift test               # unit tests
swift run CelistDBTests  # standalone logic harness
```

Requires macOS 14+ and Swift 6.0+.

## Layout

| Path | Contents |
|---|---|
| `Sources/CelistDBCore` | Engine-agnostic models + `DatabaseService` protocol |
| `Sources/CelistDB` | App: views, view models, ribbon, grid, SQL editor |
| `Sources/CelistDBTests` | Standalone test harness executable |
| `Tests/CelistDBCoreTests` | SwiftPM test target |
| `Scripts` | Icon generation (`make_icon.py`, `make_icns.sh`) and `.app` packaging |

See [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) for how the layers fit
together and [`../ROADMAP.md`](../ROADMAP.md) for what's next.
