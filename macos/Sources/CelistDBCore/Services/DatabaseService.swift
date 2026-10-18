import Foundation

/// Abstract data-access contract. SQLite is the MVP implementation;
/// MySQL / PostgreSQL / SQL Server become v2 implementations of this
/// same protocol, so the UI never needs to change.
public protocol DatabaseService: AnyObject {
    var databaseURL: URL { get }
    var databaseName: String { get }

    /// All tables and views in the database.
    func listObjects() throws -> [SchemaObject]

    /// Detailed schema for one table or view.
    func schema(for name: String) throws -> TableSchema

    /// The original `CREATE TABLE`/`CREATE VIEW` statement for an object, if known.
    func createSQL(for object: String) throws -> String?

    /// Total row count for a table (view rows aren't counted).
    func rowCount(for table: String) throws -> Int64

    /// A paged set of rows for the grid.
    func fetchRows(in table: String, state: GridState) throws -> (rows: [DataRow], totalCount: Int64)

    /// Values currently allowed by a foreign key target (for dropdowns).
    func displayValues(forColumn column: String, in table: String) throws -> [CellValue]

    /// Inserts a new row with the given column values.
    func insertRow(in table: String, values: [String: CellValue]) throws -> Int64

    /// Updates a single cell identified by its rowid.
    func updateCell(_ value: CellValue, column: String, rowID: Int64, in table: String) throws

    /// Deletes the row with the given rowid.
    func deleteRow(rowID: Int64, in table: String) throws

    /// Runs SQL, returning the last data-bearing result plus any error spans.
    func runSQL(_ sql: String) throws -> QueryResult

    /// Creates a table from a visual design.
    func createTable(_ design: TableDesign) throws

    /// Drops a table.
    func dropTable(_ table: String) throws

    /// Closes the underlying connection.
    func close()
}

public extension DatabaseService {
    var databaseName: String { databaseURL.deletingPathExtension().lastPathComponent }
}