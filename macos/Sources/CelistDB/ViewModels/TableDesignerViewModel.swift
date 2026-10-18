import Foundation
import Combine
import CelistDBCore

/// Backs the visual table designer: manages columns and renders the SQL
/// that will create the table.
@MainActor
final class TableDesignerViewModel: ObservableObject {
    let service: DatabaseService

    @Published var tableName = ""
    @Published var columns: [DesignerColumn] = []
    @Published var foreignKeyTargets: [ForeignKeyRef] = []
    @Published var errorMessage: String?
    @Published var successMessage: String?
    /// Fired after a table is successfully created so AppState can refresh
    /// the sidebar list of tables.
    var onTableCreated: (() -> Void)?

    init(service: DatabaseService) {
        self.service = service
        loadForeignKeyTargets()
    }

    func loadForeignKeyTargets() {
        do {
            let objects = try service.listObjects()
            var refs: [ForeignKeyRef] = []
            for object in objects where object.kind == .table {
                let schema = try service.schema(for: object.name)
                // Offer the primary-key column(s) as FK targets; fall back to
                // any UNIQUE column when a table has no declared primary key.
                let pkColumns = schema.primaryKeyColumns
                if pkColumns.isEmpty {
                    for index in schema.indexes where index.isUnique {
                        if let col = index.columns.first {
                            refs.append(ForeignKeyRef(table: object.name, column: col))
                        }
                    }
                } else {
                    for col in pkColumns {
                        refs.append(ForeignKeyRef(table: object.name, column: col))
                    }
                }
            }
            foreignKeyTargets = refs
        } catch {
            // FK suggestions are best-effort.
        }
    }

    func startWithSampleColumns() {
        let sample: [(String, SQLiteType, Bool, Bool)] = [
            ("id", .integer, true, true),
            ("name", .text, false, false),
            ("email", .text, false, false),
            ("is_active", .boolean, false, false),
            ("created_at", .datetime, false, false),
        ]
        columns = sample.map {
            DesignerColumn(
                name: $0.0,
                type: $0.1,
                isPrimaryKey: $0.2,
                isAutoIncrement: $0.3
            )
        }
        if tableName.isEmpty { tableName = "new_table" }
    }

    func addColumn() {
        columns.append(DesignerColumn())
    }

    func removeColumn(_ col: DesignerColumn) {
        columns.removeAll { $0.id == col.id }
    }

    func moveColumn(id: UUID, offset: Int) {
        guard let from = columns.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard columns.indices.contains(to) else { return }
        columns.swapAt(from, to)
    }

    /// SQL shown live in the designer; generated from the current design.
    var previewSQL: String {
        guard !columns.isEmpty else {
            return tableName.isEmpty
                ? "-- Add at least one column to your table."
                : "CREATE TABLE \(quoted(tableName)) (\n  -- add columns…\n)"
        }
        var parts: [String] = []
        for col in columns {
            parts.append(columnClause(col))
        }
        // Mirror `SQLiteService.createTable`: an INTEGER PRIMARY KEY
        // AUTOINCREMENT is declared inline, so only the remaining PK columns
        // need a table-level constraint (otherwise the preview would emit a
        // duplicate/incorrect PRIMARY KEY clause).
        let tableLevelPKs = columns.filter { $0.isPrimaryKey && !($0.isAutoIncrement && $0.type == .integer) }
        if !tableLevelPKs.isEmpty {
            let pkCols = tableLevelPKs.map { quoted($0.name) }.joined(separator: ", ")
            parts.append("PRIMARY KEY (\(pkCols))")
        }
        return "CREATE TABLE \(quoted(tableName)) (\n  " + parts.joined(separator: ",\n  ") + "\n)"
    }

    func save() {
        let design = TableDesign(name: tableName, columns: columns)
        do {
            try validate(design)
            try service.createTable(design)
            let created = design.name.trimmingCharacters(in: .whitespaces)
            reset()
            successMessage = "Created table “\(created)”."
            errorMessage = nil
            onTableCreated?()
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    func reset() {
        tableName = ""
        columns = []
        successMessage = nil
    }

    private func validate(_ design: TableDesign) throws {
        let name = design.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { throw DesignError("Give your table a name.") }
        if design.columns.filter(\.valid).isEmpty {
            throw DesignError("Add at least one column with a name.")
        }
        let names = design.columns.map { $0.name.lowercased() }
        if Set(names).count != names.count {
            throw DesignError("Column names must be unique.")
        }
    }

    private func columnClause(_ col: DesignerColumn) -> String {
        var out = "\(quoted(col.name)) \(col.type.rawValue)"
        if col.isPrimaryKey && col.isAutoIncrement && col.type == .integer {
            return out + " PRIMARY KEY AUTOINCREMENT"
        }
        if col.isAutoIncrement && col.type == .integer {
            out += " AUTOINCREMENT"
        }
        if col.isNotNull { out += " NOT NULL" }
        if col.isUnique && !col.isPrimaryKey { out += " UNIQUE" }
        let def = col.defaultValue.trimmingCharacters(in: .whitespaces)
        if !def.isEmpty { out += " DEFAULT \(def)" }
        if let fk = col.foreignKey {
            out += " REFERENCES \(quoted(fk.table)) (\(quoted(fk.column)))"
        }
        return out
    }

    private func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct DesignError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}