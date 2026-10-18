# Contributing to celist.db

Thanks for wanting to help. This project is deliberately small and pragmatic:
**the goal is a database app a non-developer can use**, so the bar for a change
is "does this make that easier?" — not "is this clever?"

## Ways to help

- 🐛 **Report bugs** — include your OS, the edition (macOS / Windows), the steps
  to reproduce, and the database file if it isn't sensitive.
- 💡 **Request features** — describe the *task* you were trying to do; that tells
  us more than a proposed API.
- 📝 **Improve the docs** — typos, unclear steps, and missing screenshots are all
  valid pull requests.
- 🔧 **Send code** — see the checklist below.

## Development setup

### macOS edition

Requires macOS 14+, Xcode command line tools, and Swift 6.0 (or newer).

```bash
cd macos
swift build              # compile
swift run                # launch the app
swift run CelistDBTests  # standalone logic harness (works with CLT only)
swift test               # XCTest suite (requires a full Xcode install)
./Scripts/make_app.sh    # assemble dist/celist.db.app + dist/celist.db.zip
```

Regenerating the app icon (requires Pillow):

```bash
python3 Scripts/make_icon.py   # writes the 1024px master
./Scripts/make_icns.sh         # master -> Scripts/AppIcon.icns
```

### Windows edition

Requires Node.js 18+.

```bash
cd windows
npm install
npm start          # launch
npm run dist       # portable + installer .exe into dist/
```

### pandas companion

Requires Python 3.9+.

```bash
cd tools/pycelist
python3 -m unittest discover -s tests -v   # 21 tests
python3 -m celistdb info <some.db>         # run without installing
```

Or install the `celist` console script with `pip install -e tools/pycelist`.

## Code conventions

- **Views never touch the database.** All persistence goes through
  `DatabaseService` (`macos/Sources/CelistDBCore/Services/DatabaseService.swift`).
- **Keep the product vocabulary simple**: table, column, row, relationship.
  Avoid jargon in user-facing strings.
- **Empty states matter.** Any new panel that can be empty should explain what
  to do next, not show a blank box.
- **SQL is shown before it runs.** If a feature generates SQL, surface it.
- Match the surrounding style — the code uses the standard Swift API design
  guidelines and small, focused view models.
- Hidden gotcha: the Windows edition keeps the database in memory via sql.js, so
  **every mutation must be persisted back to disk** (see `persist()` in
  `windows/src/renderer.js`).
- In `tools/pycelist`, never open a database for writing — the tool's whole
  safety story is SQLite `mode=ro`, and `tests/test_export.py` enforces it.
  Keep user-facing failures as `CelistDBError` so the CLI prints one clean line
  instead of a traceback.

## Pull request checklist

- [ ] `cd macos && swift build` then `swift run CelistDBTests` passes (if you
      touched Swift code; `swift test` too if you have Xcode installed)
- [ ] `cd tools/pycelist && python3 -m unittest discover -s tests` passes (if
      you touched the pandas companion)
- [ ] `cd windows && npm start` launches without console errors (if you touched
      the Electron app)
- [ ] New user-facing strings are plain language, and any binding that can be
      empty has an empty state
- [ ] README / docs updated if behavior or commands changed
- [ ] Commit messages are short and imperative (`Add FK picker to datasheet`)

## License

By contributing you agree your work is released under the [MIT License](LICENSE).
