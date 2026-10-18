import XCTest
@testable import CelistDBCore
import Foundation

final class CelistDBCoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dvtest-\(UUID().uuidString).db")
    }

    private func makeService() throws -> (SQLiteService, URL) {
        let url = tempURL()
        try SampleDatabase.create(at: url)
        let svc = try SQLiteService(url: url)
        return (svc, url)
    }

    // MARK: - Sample data

    func testSampleDatabaseContents() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let objects = try svc.listObjects()
        XCTAssertTrue(objects.contains { $0.name == "customers" && $0.kind == .table })
        XCTAssertTrue(objects.contains { $0.name == "products" && $0.kind == .table })
        XCTAssertTrue(objects.contains { $0.name == "orders" && $0.kind == .table })

        XCTAssertEqual(try svc.rowCount(for: "customers"), 4)
        XCTAssertEqual(try svc.rowCount(for: "products"), 4)
        XCTAssertEqual(try svc.rowCount(for: "orders"), 6)
    }

    // MARK: - Schema introspection

    func testSchemaIntrospection() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let customers = try svc.schema(for: "customers")
        XCTAssertEqual(customers.primaryKeyColumns, ["id"])
        XCTAssertTrue(customers.columns.contains { $0.name == "email" })
        XCTAssertEqual(customers.foreignKeys.count, 0)

        let orders = try svc.schema(for: "orders")
        XCTAssertEqual(orders.foreignKeys.count, 2)
        XCTAssertTrue(orders.foreignKeys.contains { $0.destinationTable == "customers" })
        XCTAssertTrue(orders.foreignKeys.contains { $0.destinationTable == "products" })
    }

    // MARK: - CRUD

    func testInsertFetchUpdateDelete() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let newID = try svc.insertRow(in: "customers", values: [
            "name": .text("Epsilon"),
            "is_vip": .bool(true),
        ])
        XCTAssertGreaterThan(newID, 0)
        XCTAssertEqual(try svc.rowCount(for: "customers"), 5)

        try svc.updateCell(.text("epsilon@example.com"), column: "email", rowID: newID, in: "customers")

        let fetched = try svc.fetchRows(in: "customers", state: GridState())
        let row = fetched.rows.first { $0.rowID == newID }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.values["email"], .text("epsilon@example.com"))
        XCTAssertEqual(row?.values["is_vip"], .integer(1))

        try svc.deleteRow(rowID: newID, in: "customers")
        XCTAssertEqual(try svc.rowCount(for: "customers"), 4)
    }

    // MARK: - Sort / filter / paging

    func testSortFilterPaging() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let sorted = try svc.fetchRows(in: "customers", state: GridState(sortColumn: "name", ascending: true))
        let names = sorted.rows.map { ($0.values["name"] ?? .null).displayText }
        XCTAssertEqual(names, names.sorted())

        let filtered = try svc.fetchRows(in: "customers", state: GridState(searchText: "Springfield"))
        XCTAssertEqual(filtered.rows.count, 2)
        XCTAssertEqual(filtered.totalCount, 2)

        let page = try svc.fetchRows(in: "customers", state: GridState(limit: 2, offset: 0))
        XCTAssertEqual(page.rows.count, 2)
        XCTAssertEqual(page.totalCount, 4)
    }

    // MARK: - Table designer + DDL

    func testCreateTableFromDesign() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let design = TableDesign(name: "notes", columns: [
            DesignerColumn(name: "id", type: .integer, isPrimaryKey: true, isAutoIncrement: true),
            DesignerColumn(name: "body", type: .text, isNotNull: true),
            DesignerColumn(name: "customer_id", type: .integer, foreignKey: ForeignKeyRef(table: "customers", column: "id")),
        ])
        try svc.createTable(design)

        let schema = try svc.schema(for: "notes")
        XCTAssertEqual(schema.columns.map(\.name), ["id", "body", "customer_id"])
        XCTAssertEqual(schema.primaryKeyColumns, ["id"])
        XCTAssertEqual(schema.foreignKeys.count, 1)
        XCTAssertEqual(schema.foreignKeys.first?.destinationTable, "customers")

        try svc.dropTable("notes")
        XCTAssertFalse(try svc.listObjects().contains { $0.name == "notes" })
    }

    // MARK: - Foreign key enforcement

    func testForeignKeyEnforcement() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(
            try svc.insertRow(in: "orders", values: [
                "customer_id": .integer(9999),
                "product_id": .integer(1),
                "quantity": .integer(1),
            ])
        )
    }

    // MARK: - SQL execution

    func testRunSQLQuery() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let result = try svc.runSQL("SELECT name, is_vip FROM customers WHERE is_vip = 1;")
        XCTAssertTrue(result.isDataQuery)
        XCTAssertEqual(result.columns, ["name", "is_vip"])
        XCTAssertEqual(result.rows.count, 2)
    }

    func testRunSQLDML() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let result = try svc.runSQL("UPDATE customers SET city = 'N/A' WHERE id = 1")
        XCTAssertFalse(result.isDataQuery)
        XCTAssertEqual(result.rowCount, 1)
    }

    func testRunSQLMultiStatement() throws {
        let (svc, url) = try makeService()
        defer { svc.close(); try? FileManager.default.removeItem(at: url) }

        let result = try svc.runSQL("""
            CREATE TABLE temp_notes (id INTEGER PRIMARY KEY, title TEXT);
            INSERT INTO temp_notes (title) VALUES ('hello');
            SELECT * FROM temp_notes
            """)
        XCTAssertTrue(result.isDataQuery)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.columns, ["id", "title"])
    }

    // MARK: - CellValue parsing

    func testCellValueParing() {
        XCTAssertEqual(CellValue.parse("", affinity: .integer), .null)
        XCTAssertEqual(CellValue.parse("42", affinity: .integer), .integer(42))
        XCTAssertEqual(CellValue.parse("4.5", affinity: .real), .real(4.5))
        XCTAssertEqual(CellValue.parse("yes", affinity: .boolean), .bool(true))
        XCTAssertEqual(CellValue.parse("apple", affinity: .text), .text("apple"))
        XCTAssertEqual(CellValue.parse("not-a-number", affinity: .integer), .text("not-a-number"))
    }

    // MARK: - SQL statement splitting

    func testSqlStatementSplitting() {
        let statements = SqliteMultiStatement.parse("""
            SELECT 1; -- a comment with ; inside
            INSERT INTO t (name) VALUES ('semi;colon', "also;here")
            """)
        XCTAssertEqual(statements.count, 2)
        XCTAssertTrue(statements[0].contains("SELECT 1"))
        XCTAssertTrue(statements[1].contains("INSERT INTO t"))
        XCTAssertTrue(statements[1].contains("'semi;colon'"))
        XCTAssertTrue(statements[1].contains("\"also;here\""))
    }

    // MARK: - Type suggestion

    func testTypeSuggestion() {
        XCTAssertEqual(SQLiteType.suggested(for: "email"), .text)
        XCTAssertEqual(SQLiteType.suggested(for: "id"), .integer)
        XCTAssertEqual(SQLiteType.suggested(for: "price"), .real)
        XCTAssertEqual(SQLiteType.suggested(for: "quantity"), .integer)
        XCTAssertEqual(SQLiteType.suggested(for: "is_active"), .boolean)
        XCTAssertEqual(SQLiteType.suggested(for: "created_at"), .datetime)
    }
}