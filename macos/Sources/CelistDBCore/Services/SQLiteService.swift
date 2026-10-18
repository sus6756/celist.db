import Foundation
import GRDB

/// GRDB-backed SQLite implementation of `DatabaseService`.
public final class SQLiteService: DatabaseService {
    public let databaseURL: URL
    private var dbQueue: DatabaseQueue

    public init(url: URL) throws {
        self.databaseURL = url
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            db.trace { _ in }  // silences logging; kept minimal
        }
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: configuration)
    }

    public func close() {
        try? dbQueue.close()
    }

    // MARK: - Schema browsing

    public func listObjects() throws -> [SchemaObject] {
        try dbQueue.read { db in
            let sql = """
                SELECT name, type
                FROM sqlite_master
                WHERE type IN ('table', 'view')
                  AND name NOT LIKE 'sqlite_%'
                ORDER BY type DESC, name COLLATE NOCASE
                """
            return try Row.fetchAll(db, sql: sql).compactMap { row in
                guard
                    let name = row["name"] as? String,
                    let type = row["type"] as? String
                else { return nil }
                guard let kind = SchemaObjectKind(rawValue: type) else { return nil }
                return SchemaObject(name: name, kind: kind)
            }
        }
    }

    public func schema(for name: String) throws -> TableSchema {
        try dbQueue.read { db in
            let isView = try db.viewExists(name)
            let rawColumns = try db.columns(in: name)
            let columns = rawColumns.map {
                SchemaColumn(
                    name: $0.name,
                    type: $0.type,
                    isNotNull: $0.isNotNull,
                    defaultValueSQL: $0.defaultValueSQL,
                    primaryKeyIndex: $0.primaryKeyIndex
                )
            }

            // Views have no primary key, foreign keys, or indexes — asking
            // SQLite for them throws, so guard on the object kind.
            let pkColumns: [String]
            let fks: [ForeignKeyInfo]
            let indexes: [IndexInfo]
            if isView {
                pkColumns = []
                fks = []
                indexes = []
            } else {
                pkColumns = try db.primaryKey(name).columns

                fks = try db.foreignKeys(on: name).map {
                    ForeignKeyInfo(
                        id: $0.id,
                        originColumns: $0.originColumns,
                        destinationTable: $0.destinationTable,
                        destinationColumns: $0.destinationColumns
                    )
                }

                indexes = (try db.indexes(on: name)).map {
                    IndexInfo(name: $0.name, columns: $0.columns, isUnique: $0.isUnique)
                }
            }

            return TableSchema(
                name: name,
                isView: isView,
                columns: columns,
                primaryKeyColumns: pkColumns,
                foreignKeys: fks,
                indexes: indexes
            )
        }
    }

    public func rowCount(for table: String) throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table.quotedDatabaseIdentifier)") ?? 0
        }
    }

    public func createSQL(for object: String) throws -> String? {
        try dbQueue.read { db in
            let sql = """
                SELECT sql FROM sqlite_master
                WHERE name = ?
                  AND type IN ('table', 'view')
                LIMIT 1
                """
            return try String.fetchOne(db, sql: sql, arguments: [object])
        }
    }

    // MARK: - Grid

    public func fetchRows(in table: String, state: GridState) throws -> (rows: [DataRow], totalCount: Int64) {
        try dbQueue.read { db in
            let quoted = table.quotedDatabaseIdentifier
            // Views have no `rowid`; query them plainly and synthesise stable
            // in-page row identifiers so the (read-only) grid can still render.
            let isView = try db.viewExists(table)

            var whereSQL = ""
            if !state.searchText.isEmpty {
                let cols = try db.columns(in: table).map { $0.name.quotedDatabaseIdentifier }
                let q = state.searchText
                    .replacingOccurrences(of: "'", with: "''")
                let likeClauses = cols.map { "\($0) LIKE '%\(q)%'" }
                whereSQL = " WHERE " + likeClauses.joined(separator: " OR ")
            }

            let total = try Int64.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(quoted)\(whereSQL)"
            ) ?? 0

            var orderSQL = ""
            if let col = state.sortColumn {
                orderSQL = " ORDER BY \(col.quotedDatabaseIdentifier) \(state.ascending ? "ASC" : "DESC")"
            }

            let rowsSQL = isView
                ? """
                  SELECT *
                  FROM \(quoted)\(whereSQL)\(orderSQL)
                  LIMIT \(state.limit) OFFSET \(state.offset)
                  """
                : """
                  SELECT *, rowid AS __datarowid
                  FROM \(quoted)\(whereSQL)\(orderSQL)
                  LIMIT \(state.limit) OFFSET \(state.offset)
                  """

            let fetched = try Row.fetchAll(db, sql: rowsSQL)
            var rows: [DataRow] = []
            rows.reserveCapacity(fetched.count)
            for (index, row) in fetched.enumerated() {
                let rowID: Int64
                if isView {
                    rowID = Int64(state.offset + index)
                } else {
                    let rawID: (any DatabaseValueConvertible)? = row["__datarowid"]
                    guard let id = Self.int64Value(from: rawID) else { continue }
                    rowID = id
                }
                var dict: [String: CellValue] = [:]
                for col in row.columnNames {
                    if col == "__datarowid" { continue }
                    dict[col] = Self.cellValue(from: row[col])
                }
                rows.append(DataRow(rowID: rowID, values: dict))
            }
            return (rows, total)
        }
    }

    public func displayValues(forColumn column: String, in table: String) throws -> [CellValue] {
        try dbQueue.read { db in
            let sql = "SELECT DISTINCT \(column.quotedDatabaseIdentifier) FROM \(table.quotedDatabaseIdentifier) ORDER BY 1"
            return try Row.fetchAll(db, sql: sql).map { Self.cellValue(from: $0[0]) }
        }
    }

    // MARK: - Mutations

    public func insertRow(in table: String, values: [String: CellValue]) throws -> Int64 {
        try dbQueue.write { db in
            if values.isEmpty {
                try db.execute(sql: "INSERT INTO \(table.quotedDatabaseIdentifier) DEFAULT VALUES")
                return db.lastInsertedRowID
            }
            let cols = Array(values.keys)
            let quotedCols = cols.map { $0.quotedDatabaseIdentifier }.joined(separator: ", ")
            let placeholders = Array(repeating: "?", count: cols.count).joined(separator: ", ")
            let sql = "INSERT INTO \(table.quotedDatabaseIdentifier) (\(quotedCols)) VALUES (\(placeholders))"
            let arguments = StatementArguments(values.values.map { Self.databaseValue($0) })
            try db.execute(sql: sql, arguments: arguments)
            return db.lastInsertedRowID
        }
    }

    public func updateCell(_ value: CellValue, column: String, rowID: Int64, in table: String) throws {
        try dbQueue.write { db in
            let sql = """
                UPDATE \(table.quotedDatabaseIdentifier)
                SET \(column.quotedDatabaseIdentifier) = ?
                WHERE rowid = ?
                """
            try db.execute(
                sql: sql,
                arguments: StatementArguments([Self.databaseValue(value), DatabaseValue(value: rowID) ?? .null])
            )
        }
    }

    public func deleteRow(rowID: Int64, in table: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM \(table.quotedDatabaseIdentifier) WHERE rowid = ?",
                arguments: StatementArguments([rowID])
            )
        }
    }

    // MARK: - SQL

    public func runSQL(_ sql: String) throws -> QueryResult {
        try dbQueue.inDatabase { db in
            var finalResult = QueryResult.empty
            var statementIndex = 0

            let statements = SqliteMultiStatement.parse(sql)
            for statementSQL in statements {
                statementIndex += 1
                let stmt = try db.makeStatement(sql: statementSQL)
                let hasRows = !stmt.columnNames.isEmpty
                if hasRows {
                    let cursor = try Row.fetchCursor(stmt)
                    var gridRows: [DataRow] = []
                    var index: Int64 = 0
                    while let row = try cursor.next() {
                        var dict: [String: CellValue] = [:]
                        for col in row.columnNames {
                            dict[col] = Self.cellValue(from: row[col])
                        }
                        gridRows.append(DataRow(rowID: index, values: dict))
                        index += 1
                    }
                    finalResult = QueryResult(
                        columns: stmt.columnNames,
                        rows: gridRows,
                        statementIndex: statementIndex,
                        rowCount: 0,
                        isDataQuery: true
                    )
                } else {
                    _ = try stmt.execute()
                    finalResult = QueryResult(
                        columns: [],
                        rows: [],
                        statementIndex: statementIndex,
                        rowCount: Int64(db.changesCount),
                        isDataQuery: false
                    )
                }
            }
            return finalResult
        }
    }

    // MARK: - DDL / designers

    public func createTable(_ design: TableDesign) throws {
        try dbQueue.write { db in
            let name = design.name.trimmingCharacters(in: .whitespaces)
            var parts: [String] = []

            for col in design.columns {
                parts.append(Self.createColumnClause(col))
            }

            let pks = design.columns.filter(\.isPrimaryKey)
            // An INTEGER PRIMARY KEY AUTOINCREMENT is already declared inline,
            // so only remaining PK columns need a table-level constraint.
            let tableLevelPKs = pks.filter { !($0.isAutoIncrement && $0.type == .integer) }
            if !tableLevelPKs.isEmpty {
                let pkCols = tableLevelPKs.map { $0.name.quotedDatabaseIdentifier }.joined(separator: ", ")
                parts.append("PRIMARY KEY (\(pkCols))")
            }

            let sql = "CREATE TABLE \(name.quotedDatabaseIdentifier) (\n  " + parts.joined(separator: ",\n  ") + "\n)"
            try db.execute(sql: sql)
        }
    }

    public func dropTable(_ table: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS \(table.quotedDatabaseIdentifier)")
        }
    }

    // MARK: - Helpers

    private static func createColumnClause(_ col: DesignerColumn) -> String {
        var out = "\(col.name.quotedDatabaseIdentifier) \(col.type.rawValue)"

        if col.isPrimaryKey && col.isAutoIncrement && col.type == .integer {
            out += " PRIMARY KEY AUTOINCREMENT"
        } else if col.isAutoIncrement && col.type == .integer {
            out += " AUTOINCREMENT"
        }

        if col.isPrimaryKey && !(col.isAutoIncrement && col.type == .integer) {
            // composite/regular PKs are added as a table-level constraint,
            // but a single non-autoincrement PK column can be declared inline.
        }

        if col.isNotNull { out += " NOT NULL" }
        if col.isUnique && !col.isPrimaryKey { out += " UNIQUE" }

        let def = col.defaultValue.trimmingCharacters(in: .whitespaces)
        if !def.isEmpty {
            out += " DEFAULT \(def)"
        }

        if let fk = col.foreignKey {
            out += " REFERENCES \(fk.table.quotedDatabaseIdentifier) (\(fk.column.quotedDatabaseIdentifier))"
        }

        return out
    }

    /// Renders a GRDB `DatabaseValue` into our `CellValue`.
    private static func cellValue(from dbValue: (any DatabaseValueConvertible)?) -> CellValue {
        switch dbValue {
        case let v as Int64: return .integer(v)
        case let v as Int: return .integer(Int64(v))
        case let v as Double: return .real(v)
        case let v as String: return .text(v)
        case let v as Data: return .blob(v)
        case let v as Bool: return .bool(v)
        default: return .null
        }
    }

    private static func int64Value(from value: (any DatabaseValueConvertible)?) -> Int64? {
        guard let value else { return nil }
        if let i = value as? Int64 { return i }
        if let b = value as? Bool { return b ? 1 : 0 }
        if let i = value as? Int { return Int64(i) }
        if let s = value as? String, let i = Int64(s) { return i }
        return nil
    }

    /// Renders our `CellValue` into a GRDB `DatabaseValueConvertible`.
    private static func databaseValue(_ value: CellValue) -> (any DatabaseValueConvertible)? {
        switch value {
        case .null: return nil
        case .integer(let v): return v
        case .real(let v): return v
        case .text(let s): return s
        case .blob(let d): return d
        case .bool(let b): return b
        }
    }
}

/// A tiny, dependency-free splitter for user-supplied SQL that separates
/// statements at semicolons (aware of quoted strings and comments).
public enum SqliteMultiStatement {
    public static func parse(_ sql: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var inLineComment = false
        var i = sql.startIndex

        while i < sql.endIndex {
            if i == sql.startIndex || i > sql.startIndex {
                let c = sql[i]
                let next = sql.index(after: i)

                if inLineComment {
                    if c == "\n" {
                        inLineComment = false
                        current.append(c)
                        i = next
                        continue
                    }
                    current.append(c)
                    i = next
                    continue
                }

                if inSingleQuote {
                    current.append(c)
                    if c == "'" && next < sql.endIndex && sql[next] == "'" {
                        current.append("'")
                        i = sql.index(after: next)
                        continue
                    } else if c == "'" {
                        inSingleQuote = false
                    }
                    i = next
                    continue
                }

                if inDoubleQuote {
                    current.append(c)
                    if c == "\"" { inDoubleQuote = false }
                    i = next
                    continue
                }

                // not in any quote/comment
                if c == "-" && next < sql.endIndex && sql[next] == "-" {
                    inLineComment = true
                    current.append("--")
                    i = sql.index(after: next)
                    continue
                }
                if c == ";" {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isRealStatement(current) { result.append(trimmed) }
                    current = ""
                    i = next
                    continue
                }
                if c == "'" { inSingleQuote = true; current.append(c); i = next; continue }
                if c == "\"" { inDoubleQuote = true; current.append(c); i = next; continue }

                current.append(c)
                i = next
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRealStatement(current) { result.append(trimmed) }
        return result
    }

    /// True when the text contains SQL beyond line comments and whitespace.
    /// Comment-only input is treated as an empty statement and skipped.
    private static func isRealStatement(_ text: String) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = line
            if let range = line.range(of: "--") {
                line = line[..<range.lowerBound]
            }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
        }
        return false
    }
}