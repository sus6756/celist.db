import Foundation

/// A database object (table or view) shown in the sidebar browser.
public enum SchemaObjectKind: String, Equatable, Hashable, Sendable {
    case table
    case view
}

public struct SchemaObject: Identifiable, Hashable, Sendable {
    public let name: String
    public let kind: SchemaObjectKind

    public var id: String { name }

    public init(name: String, kind: SchemaObjectKind) {
        self.name = name
        self.kind = kind
    }
}

/// Declared SQLite column types offered by the visual designer.
public enum SQLiteType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case text = "TEXT"
    case integer = "INTEGER"
    case real = "REAL"
    case numeric = "NUMERIC"
    case boolean = "BOOLEAN"
    case date = "DATE"
    case datetime = "DATETIME"
    case blob = "BLOB"
    case json = "JSON"

    public var id: String { rawValue }

    /// Friendly name shown in the designer picker.
    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .integer: return "Whole Number"
        case .real: return "Decimal"
        case .numeric: return "Number (loose)"
        case .boolean: return "Yes / No"
        case .date: return "Date"
        case .datetime: return "Date & Time"
        case .blob: return "File / Blob"
        case .json: return "JSON"
        }
    }

    /// Matches a declared type string from PRAGMA (case-insensitive).
    public static func from(declaredType: String) -> SQLiteType? {
        SQLiteType.allCases.first { $0.rawValue.lowercased() == declaredType.lowercased() }
    }

    /// Guesses a column type from its name, e.g. `email` -> TEXT.
    public static func suggested(for name: String) -> SQLiteType {
        let n = name.lowercased()
        if n.isEmpty { return .text }

        if n.hasSuffix("id") || n.contains("_id")
            || n == "id" || n.hasPrefix("num") || n.hasPrefix("count")
            || n.hasPrefix("qty") || n.hasPrefix("quantity") || n.hasPrefix("price")
            || n.hasPrefix("cost") || n.hasPrefix("amount") || n.hasPrefix("total")
            || n.contains("year") || n.contains("age") || n.hasPrefix("rating")
        {
            if n == "id" || n.hasSuffix("_id") || n.hasPrefix("num") || n.hasPrefix("count")
                || n.hasPrefix("qty") || n.hasPrefix("quantity") { return .integer }
            if n.hasPrefix("price") || n.hasPrefix("cost") || n.hasPrefix("amount")
                || n.hasPrefix("total") || n.hasPrefix("rating") { return .real }
            return .integer
        }

        if n.contains("date") || n.contains("time") || n.contains("dob")
            || n.contains("created") || n.contains("updated")
        {
            // "updated" contains "date", so test the timestamps before the
            // generic date branch to keep `created_at`/`updated_at` as DATETIME.
            if n.contains("updated") || n.contains("created") || n.contains("time") || n.contains("dob") {
                return .datetime
            }
            return .date
        }

        if n.hasPrefix("is") || n.hasPrefix("has") || n.contains("active")
            || n.contains("enabled") || n.contains("flag") || n.contains("bool")
        {
            return .boolean
        }

        return .text
    }
}

/// A column as designed in the visual table designer.
public struct DesignerColumn: Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var type: SQLiteType = .text
    public var isPrimaryKey: Bool = false
    public var isAutoIncrement: Bool = false
    public var isNotNull: Bool = false
    public var isUnique: Bool = false
    public var defaultValue: String = ""
    public var foreignKey: ForeignKeyRef?

    public var valid: Bool { !name.isEmpty }

    public init(
        id: UUID = UUID(),
        name: String = "",
        type: SQLiteType = .text,
        isPrimaryKey: Bool = false,
        isAutoIncrement: Bool = false,
        isNotNull: Bool = false,
        isUnique: Bool = false,
        defaultValue: String = "",
        foreignKey: ForeignKeyRef? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isPrimaryKey = isPrimaryKey
        self.isAutoIncrement = isAutoIncrement
        self.isNotNull = isNotNull
        self.isUnique = isUnique
        self.defaultValue = defaultValue
        self.foreignKey = foreignKey
    }
}

/// A `column REFERENCES table(column)` declaration.
public struct ForeignKeyRef: Hashable, Sendable, Identifiable {
    public var id: String { "\(table)" }
    public let table: String
    public let column: String

    public init(table: String, column: String) {
        self.table = table
        self.column = column
    }
}

/// In-progress design of a table.
public struct TableDesign {
    public var name: String = ""
    public var columns: [DesignerColumn] = []

    public init(name: String = "", columns: [DesignerColumn] = []) {
        self.name = name
        self.columns = columns
    }
}