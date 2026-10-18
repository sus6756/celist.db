import Foundation

/// A column of an existing table, as read from the SQLite schema.
public struct SchemaColumn: Identifiable, Hashable, Sendable {
    public let name: String
    public let type: String
    public let isNotNull: Bool
    public let defaultValueSQL: String?
    public let primaryKeyIndex: Int // 0 = not part of PK

    public var id: String { name }

    /// The SQLite-affinity bucket we parse cell input against.
    public var affinity: ColumnAffinity {
        let t = type.uppercased()
        if t.contains("INT") { return .integer }
        if t.contains("REAL") || t.contains("FLOA") || t.contains("DOUB") { return .real }
        if t.contains("BOOL") { return .boolean }
        if t.contains("BLOB") || type.isEmpty { return .blob }
        return .text
    }

    public var sqlType: SQLiteType? { SQLiteType.from(declaredType: type) }

    public init(
        name: String,
        type: String,
        isNotNull: Bool,
        defaultValueSQL: String?,
        primaryKeyIndex: Int
    ) {
        self.name = name
        self.type = type
        self.isNotNull = isNotNull
        self.defaultValueSQL = defaultValueSQL
        self.primaryKeyIndex = primaryKeyIndex
    }
}

public enum ColumnAffinity: Sendable, Equatable {
    case text, integer, real, boolean, blob
}

public struct ForeignKeyInfo: Identifiable, Hashable, Sendable {
    public let id: Int
    public let originColumns: [String]
    public let destinationTable: String
    public let destinationColumns: [String]

    public init(id: Int, originColumns: [String], destinationTable: String, destinationColumns: [String]) {
        self.id = id
        self.originColumns = originColumns
        self.destinationTable = destinationTable
        self.destinationColumns = destinationColumns
    }
}

public struct IndexInfo: Identifiable, Hashable, Sendable {
    public let name: String
    public let columns: [String]
    public let isUnique: Bool

    public var id: String { name }

    public init(name: String, columns: [String], isUnique: Bool) {
        self.name = name
        self.columns = columns
        self.isUnique = isUnique
    }
}

/// Full schema of one table/view, used by the Data tab and header.
public struct TableSchema: Hashable, Sendable {
    public let name: String
    public let isView: Bool
    public let columns: [SchemaColumn]
    public let primaryKeyColumns: [String]
    public let foreignKeys: [ForeignKeyInfo]
    public let indexes: [IndexInfo]

    public init(
        name: String,
        isView: Bool,
        columns: [SchemaColumn],
        primaryKeyColumns: [String],
        foreignKeys: [ForeignKeyInfo],
        indexes: [IndexInfo]
    ) {
        self.name = name
        self.isView = isView
        self.columns = columns
        self.primaryKeyColumns = primaryKeyColumns
        self.foreignKeys = foreignKeys
        self.indexes = indexes
    }

    public func column(named name: String) -> SchemaColumn? {
        columns.first { $0.name == name }
    }
}

/// A cell value held in memory for the grid / result set.
public enum CellValue: Hashable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case bool(Bool)

    /// Value shown in the grid.
    public var displayText: String {
        switch self {
        case .null: return ""
        case .integer(let v): return String(v)
        case .real(let v):
            if v == v.rounded() { return String(format: "%.0f", v) }
            return String(v)
        case .text(let s): return s
        case .blob: return "‹blob›"
        case .bool(let b): return b ? "1" : "0"
        }
    }

    /// A GRDB-usable binding value.
    public var bindingValue: (any Sendable)? {
        switch self {
        case .null: return nil
        case .integer(let v): return v
        case .real(let v): return v
        case .text(let s): return s
        case .blob(let d): return d
        case .bool(let b): return b
        }
    }

    /// Parses raw user input into a typed value for a given affinity.
    /// Empty input maps to NULL.
    public static func parse(_ text: String, affinity: ColumnAffinity) -> CellValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .null }

        switch affinity {
        case .integer:
            if let v = Int64(trimmed) { return .integer(v) }
            return .text(trimmed)
        case .real:
            if let v = Double(trimmed) { return .real(v) }
            return .text(trimmed)
        case .boolean:
            switch trimmed.lowercased() {
            case "1", "true", "yes", "y", "t": return .bool(true)
            case "0", "false", "no", "n", "f": return .bool(false)
            default: return .text(trimmed)
            }
        case .blob, .text:
            return .text(trimmed)
        }
    }
}

/// One row loaded into the data grid, keyed by rowid.
public struct DataRow: Identifiable, Sendable {
    public let rowID: Int64
    public let values: [String: CellValue]

    public var id: Int64 { rowID }

    public init(rowID: Int64, values: [String: CellValue]) {
        self.rowID = rowID
        self.values = values
    }
}

public struct ConstraintRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let originColumns: String
    public let destinationTable: String
    public let destinationColumns: String

    public init(_ fk: ForeignKeyInfo) {
        id = fk.id
        originColumns = fk.originColumns.joined(separator: ", ")
        destinationTable = fk.destinationTable
        destinationColumns = fk.destinationColumns.joined(separator: ", ")
    }
}