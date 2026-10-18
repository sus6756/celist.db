import Foundation
import CelistDBCore

/// Standalone logic-test harness for CelistDBCore.
/// The CLT-only toolchain here ships neither XCTest nor swift-testing,
/// so scenarios run through plain assertions. Exits non-zero on failure.

private nonisolated(unsafe) var failures = 0
private nonisolated(unsafe) var testsRun = 0

func check(_ condition: Bool, _ name: String) {
    testsRun += 1
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func throwsError<T>(_ body: () throws -> T) -> Bool {
    do { _ = try body(); return false } catch { return true }
}

func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dvtest-\(UUID().uuidString).db")
}

func makeService() throws -> (SQLiteService, URL) {
    let url = tempURL()
    try SampleDatabase.create(at: url)
    let svc = try SQLiteService(url: url)
    return (svc, url)
}

func withDB<T>(_ body: (SQLiteService) throws -> T) throws -> T {
    let (svc, url) = try makeService()
    defer {
        svc.close()
        try? FileManager.default.removeItem(at: url)
    }
    return try body(svc)
}

// MARK: - Scenario runners

func testSampleDatabaseContents() throws {
    try withDB { svc in
        let objects = try svc.listObjects()
        check(objects.contains { $0.name == "customers" && $0.kind == .table }, "sample lists customers table")
        check(objects.contains { $0.name == "products" && $0.kind == .table }, "sample lists products table")
        check(objects.contains { $0.name == "orders" && $0.kind == .table }, "sample lists orders table")

        check(try svc.rowCount(for: "customers") == 4, "customers row count == 4")
        check(try svc.rowCount(for: "products") == 4, "products row count == 4")
        check(try svc.rowCount(for: "orders") == 6, "orders row count == 6")
    }
}

func testSchemaIntrospection() throws {
    try withDB { svc in
        let customers = try svc.schema(for: "customers")
        check(customers.primaryKeyColumns == ["id"], "customers PK is [id]")
        check(customers.columns.contains { $0.name == "email" }, "customers has email column")
        check(customers.foreignKeys.isEmpty, "customers has no FKs")

        let orders = try svc.schema(for: "orders")
        check(orders.foreignKeys.count == 2, "orders has 2 FKs")
        check(orders.foreignKeys.contains { $0.destinationTable == "customers" }, "orders FK -> customers")
        check(orders.foreignKeys.contains { $0.destinationTable == "products" }, "orders FK -> products")
    }
}

func testCRUD() throws {
    try withDB { svc in
        let newID = try svc.insertRow(in: "customers", values: [
            "name": .text("Epsilon"),
            "is_vip": .integer(1),
        ])
        check(newID > 0, "insert returns new rowid")
        check(try svc.rowCount(for: "customers") == 5, "row count grows to 5")

        try svc.updateCell(.text("epsilon@example.com"), column: "email", rowID: newID, in: "customers")

        let fetched = try svc.fetchRows(in: "customers", state: GridState())
        let row = fetched.rows.first { $0.rowID == newID }
        check(row != nil, "fetched row found by rowid")
        check(row?.values["email"] == .text("epsilon@example.com"), "cell update persisted")
        check(row?.values["is_vip"] == .integer(1), "bool column round-trips as integer")

        try svc.deleteRow(rowID: newID, in: "customers")
        check(try svc.rowCount(for: "customers") == 4, "delete removes row")
    }
}

func testSortFilterPaging() throws {
    try withDB { svc in
        let sorted = try svc.fetchRows(in: "customers", state: GridState(sortColumn: "name", ascending: true))
        let names = sorted.rows.map { ($0.values["name"] ?? .null).displayText }
        check(names == names.sorted(), "sort by name ascending")

        let filtered = try svc.fetchRows(in: "customers", state: GridState(searchText: "Springfield"))
        check(filtered.rows.count == 2, "search finds 2 Springfield customers")
        check(filtered.totalCount == 2, "search reports matching total")

        let page = try svc.fetchRows(in: "customers", state: GridState(limit: 2, offset: 0))
        check(page.rows.count == 2, "limit applies")
        check(page.totalCount == 4, "paged total is full count")
    }
}

func testCreateTableFromDesign() throws {
    try withDB { svc in
        let design = TableDesign(name: "notes", columns: [
            DesignerColumn(name: "id", type: .integer, isPrimaryKey: true, isAutoIncrement: true),
            DesignerColumn(name: "body", type: .text, isNotNull: true),
            DesignerColumn(name: "customer_id", type: .integer, foreignKey: ForeignKeyRef(table: "customers", column: "id")),
        ])
        try svc.createTable(design)

        let schema = try svc.schema(for: "notes")
        check(schema.columns.map(\.name) == ["id", "body", "customer_id"], "designer table columns in order")
        check(schema.primaryKeyColumns == ["id"], "designer table PK")
        check(schema.foreignKeys.count == 1, "designer table FK count")
        check(schema.foreignKeys.first?.destinationTable == "customers", "designer table FK target")

        try svc.dropTable("notes")
        check(!(try svc.listObjects().contains { $0.name == "notes" }), "drop table removes object")
    }
}

func testForeignKeyEnforcement() throws {
    try withDB { svc in
        let violated = throwsError {
            try svc.insertRow(in: "orders", values: [
                "customer_id": .integer(9999),
                "product_id": .integer(1),
                "quantity": .integer(1),
            ])
        }
        check(violated, "invalid FK ref throws")
    }
}

func testRunSQLSelect() throws {
    try withDB { svc in
        let result = try svc.runSQL("SELECT name, is_vip FROM customers WHERE is_vip = 1;")
        check(result.isDataQuery, "SELECT yields data result")
        check(result.columns == ["name", "is_vip"], "SELECT columns match")
        check(result.rows.count == 2, "SELECT returns 2 vip rows")
    }
}

func testRunSQLDML() throws {
    try withDB { svc in
        let result = try svc.runSQL("UPDATE customers SET city = 'N/A' WHERE id = 1")
        check(!result.isDataQuery, "UPDATE is not a data query")
        check(result.rowCount == 1, "UPDATE reports 1 changed row")
    }
}

func testRunSQLMultiStatement() throws {
    try withDB { svc in
        let result = try svc.runSQL("""
            CREATE TABLE temp_notes (id INTEGER PRIMARY KEY, title TEXT);
            INSERT INTO temp_notes (title) VALUES ('hello');
            SELECT * FROM temp_notes
            """)
        check(result.isDataQuery, "multi-statement returns last SELECT")
        check(result.rows.count == 1, "multi-statement SELECT row count")
        check(result.columns == ["id", "title"], "multi-statement SELECT columns")
    }
}

func testCellValueParsing() {
    check(CellValue.parse("", affinity: .integer) == .null, "empty parses to NULL")
    check(CellValue.parse("42", affinity: .integer) == .integer(42), "integer parse")
    check(CellValue.parse("4.5", affinity: .real) == .real(4.5), "real parse")
    check(CellValue.parse("yes", affinity: .boolean) == .bool(true), "boolean parse")
    check(CellValue.parse("apple", affinity: .text) == .text("apple"), "text parse")
    check(CellValue.parse("not-a-number", affinity: .integer) == .text("not-a-number"), "integer fallback to text")
}

func testSqlStatementSplitting() {
    let statements = SqliteMultiStatement.parse("""
        SELECT 1; -- a comment with ; inside
        INSERT INTO t (name) VALUES ('semi;colon', "also;here")
        """)
    check(statements.count == 2, "splits into 2 statements")
    check(statements[0].contains("SELECT 1"), "first statement is SELECT")
    check(statements[1].contains("INSERT INTO t"), "second statement is INSERT")
    check(statements[1].contains("'semi;colon'"), "single-quoted ; preserved")
    check(statements[1].contains("\"also;here\""), "double-quoted ; preserved")
}

func testTypeSuggestion() {
    check(SQLiteType.suggested(for: "email") == .text, "email -> text")
    check(SQLiteType.suggested(for: "id") == .integer, "id -> integer")
    check(SQLiteType.suggested(for: "price") == .real, "price -> real")
    check(SQLiteType.suggested(for: "quantity") == .integer, "quantity -> integer")
    check(SQLiteType.suggested(for: "is_active") == .boolean, "is_active -> boolean")
    check(SQLiteType.suggested(for: "created_at") == .datetime, "created_at -> datetime")
}

// MARK: - Typing: cell input parsing & display

func testCellValueParsingExtended() {
    // Empty / whitespace -> NULL across every affinity.
    check(CellValue.parse("", affinity: .text) == .null, "empty -> NULL")
    check(CellValue.parse("   ", affinity: .real) == .null, "whitespace real -> NULL")
    check(CellValue.parse("\n\t", affinity: .integer) == .null, "newline/tab integer -> NULL")

    // Integer affinity.
    check(CellValue.parse("42", affinity: .integer) == .integer(42), "integer 42")
    check(CellValue.parse("-7", affinity: .integer) == .integer(-7), "integer negative")
    check(CellValue.parse("  42  ", affinity: .integer) == .integer(42), "integer trims whitespace")
    check(CellValue.parse("4.5", affinity: .integer) == .text("4.5"), "fraction falls back to text")
    check(CellValue.parse("abc", affinity: .integer) == .text("abc"), "letters fall back to text")
    check(CellValue.parse("99999999999999999999", affinity: .integer) == .text("99999999999999999999"), "integer overflow falls back to text")

    // Real affinity.
    check(CellValue.parse("4.5", affinity: .real) == .real(4.5), "real 4.5")
    check(CellValue.parse("10", affinity: .real) == .real(10.0), "real whole number")
    check(CellValue.parse("-2.5", affinity: .real) == .real(-2.5), "real negative")
    check(CellValue.parse("1e3", affinity: .real) == .real(1000.0), "real scientific notation")
    check(CellValue.parse("abc", affinity: .real) == .text("abc"), "real falls back to text")
    check(CellValue.parse("  9.5  ", affinity: .real) == .real(9.5), "real trims whitespace")

    // Boolean affinity — any case, several spellings.
    check(CellValue.parse("1", affinity: .boolean) == .bool(true), "bool 1 -> true")
    check(CellValue.parse("0", affinity: .boolean) == .bool(false), "bool 0 -> false")
    check(CellValue.parse("true", affinity: .boolean) == .bool(true), "bool true")
    check(CellValue.parse("TRUE", affinity: .boolean) == .bool(true), "bool TRUE (case-insensitive)")
    check(CellValue.parse("false", affinity: .boolean) == .bool(false), "bool false")
    check(CellValue.parse("yes", affinity: .boolean) == .bool(true), "bool yes")
    check(CellValue.parse("Yes", affinity: .boolean) == .bool(true), "bool Yes (case-insensitive)")
    check(CellValue.parse("no", affinity: .boolean) == .bool(false), "bool no")
    check(CellValue.parse("y", affinity: .boolean) == .bool(true), "bool y")
    check(CellValue.parse("n", affinity: .boolean) == .bool(false), "bool n")
    check(CellValue.parse("t", affinity: .boolean) == .bool(true), "bool t")
    check(CellValue.parse("f", affinity: .boolean) == .bool(false), "bool f")
    check(CellValue.parse("maybe", affinity: .boolean) == .text("maybe"), "bool unknown -> text")
    check(CellValue.parse("  no  ", affinity: .boolean) == .bool(false), "bool trims whitespace")

    // Text / blob affinity.
    check(CellValue.parse("hello", affinity: .text) == .text("hello"), "text hello")
    check(CellValue.parse("  hi  ", affinity: .text) == .text("hi"), "text trims whitespace")
    check(CellValue.parse("123", affinity: .blob) == .text("123"), "blob input stored as text")
}

func testCellDisplayText() {
    check(CellValue.integer(42).displayText == "42", "display integer")
    check(CellValue.real(4.5).displayText == "4.5", "display real fraction")
    check(CellValue.real(4.0).displayText == "4", "display whole real rounded")
    check(CellValue.real(10.5).displayText == "10.5", "display real 10.5")
    check(CellValue.text("hello").displayText == "hello", "display text")
    check(CellValue.bool(true).displayText == "1", "display bool true")
    check(CellValue.bool(false).displayText == "0", "display bool false")
    check(CellValue.null.displayText == "", "display null is empty")
    check(CellValue.blob(Data()).displayText == "‹blob›", "display blob marker")
}

// MARK: - Typing: column affinity

func testColumnAffinity() {
    func affinity(_ type: String) -> ColumnAffinity {
        SchemaColumn(name: "c", type: type, isNotNull: false, defaultValueSQL: nil, primaryKeyIndex: 0).affinity
    }
    check(affinity("INTEGER") == .integer, "affinity INTEGER")
    check(affinity("INT") == .integer, "affinity INT")
    check(affinity("BIGINT") == .integer, "affinity BIGINT")
    check(affinity("integer") == .integer, "affinity integer (case-insensitive)")
    check(affinity("REAL") == .real, "affinity REAL")
    check(affinity("FLOAT") == .real, "affinity FLOAT")
    check(affinity("DOUBLE") == .real, "affinity DOUBLE")
    check(affinity("DOUBLE PRECISION") == .real, "affinity DOUBLE PRECISION")
    check(affinity("BOOLEAN") == .boolean, "affinity BOOLEAN")
    check(affinity("BOOL") == .boolean, "affinity BOOL")
    check(affinity("BLOB") == .blob, "affinity BLOB")
    check(affinity("") == .blob, "affinity empty type -> blob")
    check(affinity("TEXT") == .text, "affinity TEXT")
    check(affinity("VARCHAR(255)") == .text, "affinity VARCHAR")
    check(affinity("DATETIME") == .text, "affinity DATETIME")
    check(affinity("DATE") == .text, "affinity DATE")
    check(affinity("NUMERIC") == .text, "affinity NUMERIC")
}

// MARK: - Typing: designer type auto-suggestion

func testTypeSuggestionExtended() {
    func s(_ name: String) -> SQLiteType { SQLiteType.suggested(for: name) }
    check(s("id") == .integer, "suggest id -> integer")
    check(s("customer_id") == .integer, "suggest customer_id")
    check(s("user_id") == .integer, "suggest user_id")
    check(s("order_id") == .integer, "suggest order_id")
    check(s("num_items") == .integer, "suggest num_items")
    check(s("count") == .integer, "suggest count")
    check(s("qty") == .integer, "suggest qty")
    check(s("quantity") == .integer, "suggest quantity")
    check(s("year") == .integer, "suggest year")
    check(s("birth_year") == .integer, "suggest birth_year")
    check(s("age") == .integer, "suggest age")
    check(s("price") == .real, "suggest price -> real")
    check(s("price_usd") == .real, "suggest price_usd")
    check(s("cost") == .real, "suggest cost")
    check(s("amount_due") == .real, "suggest amount_due")
    check(s("total") == .real, "suggest total")
    check(s("total_sold") == .real, "suggest total_sold")
    check(s("rating") == .real, "suggest rating")
    check(s("email") == .text, "suggest email -> text")
    check(s("name") == .text, "suggest name")
    check(s("description") == .text, "suggest description")
    check(s("sku") == .text, "suggest sku")
    check(s("FirstName") == .text, "suggest FirstName (case-insensitive)")
    check(s("") == .text, "suggest empty -> text")
    check(s("created_at") == .datetime, "suggest created_at")
    check(s("updated_at") == .datetime, "suggest updated_at")
    check(s("dob") == .datetime, "suggest dob")
    check(s("date_of_birth") == .date, "suggest date_of_birth")
    check(s("birth_date") == .date, "suggest birth_date")
    check(s("ShippingDate") == .date, "suggest ShippingDate (case-insensitive)")
    check(s("is_active") == .boolean, "suggest is_active")
    check(s("has_children") == .boolean, "suggest has_children")
    check(s("active") == .boolean, "suggest active")
    check(s("enabled") == .boolean, "suggest enabled")
    check(s("flag") == .boolean, "suggest flag")
    check(s("bool") == .boolean, "suggest bool")
}

func testSQLiteTypeFromDeclared() {
    check(SQLiteType.from(declaredType: "TEXT") == .text, "declared TEXT")
    check(SQLiteType.from(declaredType: "integer") == .integer, "declared integer (case-insensitive)")
    check(SQLiteType.from(declaredType: "INTEGER") == .integer, "declared INTEGER")
    check(SQLiteType.from(declaredType: "JSON") == .json, "declared JSON")
    check(SQLiteType.from(declaredType: "VARCHAR") == nil, "declared VARCHAR unknown")
    check(SQLiteType.from(declaredType: "INTEGER PRIMARY KEY") == nil, "declared composite unknown")
}

// MARK: - Typing: SQL statement splitting

func testSqlStatementSplittingExtended() {
    check(SqliteMultiStatement.parse("").isEmpty, "split empty -> none")
    check(SqliteMultiStatement.parse("   \n  ").isEmpty, "split whitespace -> none")
    check(SqliteMultiStatement.parse("SELECT 1;") == ["SELECT 1"], "split single statement")
    check(SqliteMultiStatement.parse("SELECT 1; SELECT 2;") == ["SELECT 1", "SELECT 2"], "split two statements")
    check(SqliteMultiStatement.parse("  SELECT 1 ;  ") == ["SELECT 1"], "split trims whitespace")
    check(SqliteMultiStatement.parse("SELECT 'a;b'; SELECT 2") == ["SELECT 'a;b'", "SELECT 2"], "semicolon inside single quotes preserved")
    check(SqliteMultiStatement.parse("SELECT \"a;b\"; SELECT 2") == ["SELECT \"a;b\"", "SELECT 2"], "semicolon inside double quotes preserved")
    check(SqliteMultiStatement.parse("INSERT INTO t VALUES ('it''s', 'x;y'); SELECT 1") == ["INSERT INTO t VALUES ('it''s', 'x;y')", "SELECT 1"], "escaped quote + semicolon in string")

    let withComment = SqliteMultiStatement.parse("SELECT 1; -- tail ; comment\nSELECT 2")
    check(withComment.count == 2, "comment does not start a new statement")
    check(withComment[0] == "SELECT 1", "first split discards comment")
    check(withComment[1] == "-- tail ; comment\nSELECT 2", "comment+sql kept together")

    check(SqliteMultiStatement.parse("-- just a comment").isEmpty, "comment-only input splits to none")
    check(SqliteMultiStatement.parse("  -- just a comment\n  ").isEmpty, "whitespace+comment splits to none")
}

// MARK: - Typing: search box (LIKE filtering)

func testSearchTyping() throws {
    try withDB { svc in
        let lower = try svc.fetchRows(in: "customers", state: GridState(searchText: "springfield"))
        check(lower.rows.count == 2, "search lowercase matches case-insensitively")

        let partial = try svc.fetchRows(in: "customers", state: GridState(searchText: "beta"))
        check(partial.rows.count == 1, "search mid-word substring")

        let phone = try svc.fetchRows(in: "customers", state: GridState(searchText: "555-0111"))
        check(phone.rows.count == 1, "search by phone number")

        _ = try svc.insertRow(in: "customers", values: ["name": .text("O'Brien")])
        let quote = try svc.fetchRows(in: "customers", state: GridState(searchText: "O'Brien"))
        check(quote.rows.count == 1, "search escapes apostrophes safely")

        let evil = try svc.fetchRows(in: "customers", state: GridState(searchText: "1' OR '1'='1"))
        check(evil.rows.count == 0, "search neutralises quote injection")

        let all = try svc.fetchRows(in: "customers", state: GridState(searchText: "%"))
        check(all.totalCount == 5, "search % acts as wildcard over all rows")

        let none = try svc.fetchRows(in: "customers", state: GridState(searchText: "zzzqqq"))
        check(none.rows.isEmpty && none.totalCount == 0, "search no match is empty")
    }
}

// MARK: - Typing: grid cell round-trip

func testGridCellRoundTrip() throws {
    try withDB { svc in
        try svc.updateCell(CellValue.parse("17", affinity: .integer), column: "in_stock", rowID: 1, in: "products")
        try svc.updateCell(CellValue.parse("9.99", affinity: .real), column: "price", rowID: 1, in: "products")
        try svc.updateCell(CellValue.parse("false", affinity: .boolean), column: "is_vip", rowID: 1, in: "customers")
        try svc.updateCell(CellValue.parse("", affinity: .text), column: "email", rowID: 1, in: "customers")

        let products = try svc.fetchRows(in: "products", state: GridState()).rows
        let p = products.first { $0.rowID == 1 }
        check(p?.values["in_stock"] == .integer(17), "integer cell round-trips")
        check(p?.values["price"] == .real(9.99), "real cell round-trips")

        let customers = try svc.fetchRows(in: "customers", state: GridState()).rows
        let c = customers.first { $0.rowID == 1 }
        check(c?.values["is_vip"] == .integer(0), "false bool stored as integer 0")
        check(c?.values["email"] == .null, "empty input clears cell to NULL")
    }
}

// MARK: - Typing: raw SQL editor run path

func testRunSQLTyping() throws {
    try withDB { svc in
        let result = try svc.runSQL("""
            INSERT INTO products (name, sku, price) VALUES ('Semi;Colon', 'SC-1', 1.5);
            -- comment with a ; inside
            SELECT name FROM products WHERE sku = 'SC-1'
            """)
        check(result.isDataQuery, "typed multi-statement returns SELECT")
        check(result.rows.count == 1, "typed INSERT then SELECT finds row")
        check(result.rows[0].values["name"] == .text("Semi;Colon"), "string with semicolon is preserved")

        let two = try svc.runSQL("SELECT 'first'; SELECT 'second' AS label")
        check(two.isDataQuery && two.rows.count == 1, "last statement wins")
        check(two.columns == ["label"], "last statement's columns returned")
        check(two.rows[0].values["label"] == .text("second"), "last statement's value returned")

        do { _ = try svc.runSQL("-- just a comment"); check(true, "comment-only SQL does not throw") }
        catch { check(false, "comment-only SQL does not throw — error: \(error)") }
    }
}

// MARK: - Typing: views, defaults, multi-statement ordering

func testViewRowFetching() throws {
    try withDB { svc in
        _ = try svc.runSQL("CREATE VIEW vip_customers AS SELECT id, name FROM customers WHERE is_vip = 1")
        let schema = try svc.schema(for: "vip_customers")
        check(schema.isView, "view schema is flagged as a view")

        let fetched = try svc.fetchRows(in: "vip_customers", state: GridState())
        check(fetched.totalCount == 2, "view reports matching row count")
        check(fetched.rows.count == 2, "view rows fetched without a rowid column")
        check(fetched.rows.allSatisfy { $0.values["name"] != nil }, "view rows carry column values")
        check(fetched.rows.first?.rowID == 0, "view rows get synthesised identifiers")
    }
}

func testInsertRowDefaultValues() throws {
    try withDB { svc in
        _ = try svc.runSQL("""
            CREATE TABLE gadgets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                label TEXT DEFAULT 'unnamed',
                qty INTEGER NOT NULL DEFAULT 0
            )
            """)
        let id = try svc.insertRow(in: "gadgets", values: [:])
        check(id > 0, "empty insert uses DEFAULT VALUES and returns a rowid")
        let rows = try svc.fetchRows(in: "gadgets", state: GridState()).rows
        check(rows.first?.values["label"] == .text("unnamed"), "column DEFAULT is applied")
        check(rows.first?.values["qty"] == .integer(0), "NOT NULL DEFAULT column is applied")
    }
}

func testRunSQLLastStatementWins() throws {
    try withDB { svc in
        let result = try svc.runSQL("SELECT * FROM customers; UPDATE customers SET city = 'X' WHERE id = 1")
        check(!result.isDataQuery, "a trailing DML statement wins over an earlier SELECT")
        check(result.rowCount == 1, "trailing DML reports the affected-row count")
    }
}

// MARK: - External data: backup + import shape

func testBackupViaVacuumInto() throws {
    try withDB { svc in
        let dest = tempURL()
        defer { try? FileManager.default.removeItem(at: dest) }
        let escaped = dest.path.replacingOccurrences(of: "'", with: "''")
        _ = try svc.runSQL("VACUUM INTO '\(escaped)'")
        check(FileManager.default.fileExists(atPath: dest.path), "VACUUM INTO writes a backup file")

        let copy = try SQLiteService(url: dest)
        defer { copy.close() }
        check(try copy.rowCount(for: "customers") == 4, "backup copy contains the rows")
        check(try copy.listObjects().contains { $0.name == "orders" }, "backup copy contains the schema")
    }
}

func testImportedTextTable() throws {
    try withDB { svc in
        // Mirrors what the CSV/JSON importer does: a TEXT table + text inserts.
        let design = TableDesign(name: "people", columns: [
            DesignerColumn(name: "name", type: .text),
            DesignerColumn(name: "city", type: .text),
        ])
        try svc.createTable(design)
        _ = try svc.insertRow(in: "people", values: ["name": .text("Zed"), "city": .text("NY")])
        _ = try svc.insertRow(in: "people", values: ["name": .text("Ada"), "city": .null])

        let rows = try svc.fetchRows(in: "people", state: GridState()).rows
        check(rows.count == 2, "imported text table holds both rows")
        check(rows.contains { $0.values["name"] == .text("Zed") }, "imported value round-trips")
        check(rows.contains { $0.values["city"] == .null }, "empty import field becomes NULL")
        let schema = try svc.schema(for: "people")
        check(schema.columns.map { $0.name } == ["name", "city"], "imported column names preserved")
    }
}

// MARK: - Main

do {
    try testSampleDatabaseContents()
    try testSchemaIntrospection()
    try testCRUD()
    try testSortFilterPaging()
    try testCreateTableFromDesign()
    try testForeignKeyEnforcement()
    try testRunSQLSelect()
    try testRunSQLDML()
    try testRunSQLMultiStatement()
    testCellValueParsing()
    testSqlStatementSplitting()
    testTypeSuggestion()
    testCellValueParsingExtended()
    testCellDisplayText()
    testColumnAffinity()
    testTypeSuggestionExtended()
    testSQLiteTypeFromDeclared()
    testSqlStatementSplittingExtended()
    try testSearchTyping()
    try testGridCellRoundTrip()
    try testRunSQLTyping()
    try testViewRowFetching()
    try testInsertRowDefaultValues()
    try testRunSQLLastStatementWins()
    try testBackupViaVacuumInto()
    try testImportedTextTable()

    print("")
    print("\(testsRun) checks, \(failures) failures")
    if failures > 0 {
        exit(1)
    }
} catch {
    print("HARNESS ERROR: \(error)")
    exit(1)
}