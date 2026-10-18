# celist.db — pandas companion

`celist` is a small, read-only command line tool that reads your celist.db
(SQLite) databases with [pandas](https://pandas.pydata.org) and writes
*properly formatted* Excel workbooks.

The app's built-in export produces plain CSV/JSON with no styling. This tool
produces `.xlsx` you can hand to someone else: branded bold headers, a frozen
header row, an autofilter, sensible column widths, and number/date formats
derived from the column dtypes — plus multi-sheet workbooks for a whole
database.

**Every command opens the database read-only** (SQLite `mode=ro`), so it can
never modify or corrupt the database you point it at.

## Install

Requires Python 3.9+.

```bash
pip install -e tools/pycelist      # from the repository root
celist --help
```

Or run it without installing anything:

```bash
cd tools/pycelist
python3 -m celistdb --help
```

Dependencies: `pandas>=2.0`, `openpyxl>=3.1`.

## Usage

### See what's in a database

```console
$ celist info shop.db
Database: shop.db
  tables (3)
    customers                    5 rows
    orders                      12 rows
    products                     4 rows
  views (1)
    revenue_by_country           3 rows
```

`--json` gives the same information for scripts.

### Export one table

```bash
celist export shop.db --table orders
# → shop-orders.xlsx beside the database

celist export shop.db --table orders -o /tmp/orders.xlsx --sheet "All orders"
```

### Export a query

Any read-only SQL works. The result keeps your column names and types.

```bash
celist export shop.db \
  --query "SELECT country, COUNT(*) AS orders, ROUND(SUM(total), 2) AS revenue
           FROM revenue_by_country ORDER BY revenue DESC" \
  --sheet "Revenue by country" -o revenue.xlsx
```

### Export a whole database

Each table gets its own sheet, and a leading **Index** sheet lists the sheets
and their sizes. Add `--include-views` to export views too.

```bash
celist export shop.db --all-tables --include-views -o shop.xlsx
# Wrote shop.xlsx — 4 sheets, 24 rows (+ Index)
```

### Options

| Flag | Meaning |
|---|---|
| `--table`, `-t` | table or view to export |
| `--query`, `-q` | read-only SQL to export |
| `--all-tables` | export every table to its own sheet |
| `--include-views` | with `--all-tables`, also export views |
| `--output`, `-o` | output path (default: beside the database) |
| `--sheet`, `-s` | sheet name for a single-source export |
| `--limit`, `-n` | export at most N rows |
| `--format`, `-f` | output format (currently `xlsx`) |
| `--no-index` | with `--all-tables`, skip the Index sheet |

Exit codes: `0` success, `1` runtime error (missing database, bad SQL, no
tables), `2` usage error. Errors are reported as `celist: error: …` on stderr.

## What the exported sheet looks like

| Behaviour | Detail |
|---|---|
| Header row | bold white text on the brand indigo `#261A54`, 20 pt tall |
| Frozen panes | header row stays visible while scrolling |
| Autofilter | dropdowns on every column |
| Column widths | fitted to the widest of the header and the first 200 values, capped at 60 |
| Integers | `#,##0` |
| Decimals | `#,##0.00` |
| Dates | `yyyy-mm-dd hh:mm` |
| `NULL` | left as an empty cell |
| BLOBs | rendered as `0x…` hex, truncated to fit |

Number formats are skipped on sheets larger than 20,000 rows to keep the
export fast; everything else still applies.

## Python API

The same machinery is importable if you want to build on it:

```python
from celistdb import connect, read_table, read_query, write_workbook

with connect("shop.db") as conn:                 # read-only
    orders = read_table("shop.db", "orders", conn=conn)
    totals = read_query("shop.db", "SELECT country, SUM(total) FROM ...", conn=conn)

write_workbook({"Orders": orders, "Totals": totals}, "report.xlsx", index_sheet=True)
```

## Tests

```bash
cd tools/pycelist
python3 -m unittest discover -s tests -v
```

21 tests cover the read-only guarantee (a `DROP TABLE` through this tool must
fail and leave the data untouched), blob/unicode/NULL handling, sheet-name
sanitising, the Index sheet, CLI output naming, `--limit`, and error reporting.

## Roadmap for this tool

This first release deliberately ships **Excel export only**. Next up, all
pandas-shaped and all fitting the app's own roadmap:

- data profiling reports (dtypes, null counts, uniques, summary stats)
- smarter CSV/JSON import (dtype inference, delimiter/header detection)
- pivot / group-by / merge without SQL, written back as a table or view
- charts from query results
- Parquet / Feather I/O for notebook handoff
