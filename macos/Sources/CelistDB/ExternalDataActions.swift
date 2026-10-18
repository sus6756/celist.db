import Foundation
import AppKit
import UniformTypeIdentifiers
import CelistDBCore

/// One foreign-key link, shown in the Relationships sheet.
struct RelationshipRow: Identifiable {
    let id = UUID()
    let fromTable: String
    let fromColumn: String
    let toTable: String
    let toColumn: String
}

/// Import / export / backup actions shared by the ribbon's External Data and
/// Database Tools tabs. Kept separate from `AppActions` (which owns the
/// open/new/sample flows) to keep each file focused.
@MainActor
enum ExternalDataActions {

    // MARK: - Import

    static func importCSV(appState: AppState) {
        guard appState.service != nil else {
            appState.openErrorMessage = "Open or create a database first."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Import CSV"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = parseCSV(text)
            guard !parsed.headers.isEmpty else {
                throw DataTransferError("The CSV file appears to be empty.")
            }
            let base = sanitize(url.deletingPathExtension().lastPathComponent)
            let (table, count) = try makeTable(headers: parsed.headers, rows: parsed.rows, baseName: base, appState: appState)
            appState.reloadAfterSchemaChange()
            inform(title: "Import complete", message: "Imported \(count) row\(count == 1 ? "" : "s") into “\(table)”.")
        } catch {
            appState.openErrorMessage = "CSV import failed: \(error.localizedDescription)"
        }
    }

    static func importJSON(appState: AppState) {
        guard appState.service != nil else {
            appState.openErrorMessage = "Open or create a database first."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Import JSON"
        panel.allowedContentTypes = [.json, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            let dicts = jsonObjects(object)
            guard !dicts.isEmpty else {
                throw DataTransferError("The JSON file contains no objects to import.")
            }
            var headers: [String] = []
            for dict in dicts {
                for key in dict.keys where !headers.contains(key) { headers.append(key) }
            }
            let rows = dicts.map { dict in
                headers.map { jsonScalar(dict[$0]) }
            }
            let base = sanitize(url.deletingPathExtension().lastPathComponent)
            let (table, count) = try makeTable(headers: headers, rows: rows, baseName: base, appState: appState)
            appState.reloadAfterSchemaChange()
            inform(title: "Import complete", message: "Imported \(count) row\(count == 1 ? "" : "s") into “\(table)”.")
        } catch {
            appState.openErrorMessage = "JSON import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    static func exportSpreadsheet(appState: AppState, title: String) {
        guard let data = exportableData(appState: appState) else {
            appState.openErrorMessage = "Open a table or run a query first, then export."
            return
        }
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = data.defaultName + ".csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let csv = csvText(columns: data.columns, rows: data.rows)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            inform(title: "Export complete", message: "Exported \(data.rows.count) row\(data.rows.count == 1 ? "" : "s") to \(url.lastPathComponent).")
        } catch {
            appState.openErrorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    static func exportJSON(appState: AppState) {
        guard let data = exportableData(appState: appState) else {
            appState.openErrorMessage = "Open a table or run a query first, then export."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export JSON"
        panel.nameFieldStringValue = data.defaultName + ".json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let objects: [[String: Any]] = data.rows.map { row in
                var dict: [String: Any] = [:]
                for (i, col) in data.columns.enumerated() where i < row.count {
                    dict[col] = row[i]
                }
                return dict
            }
            let json = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
            try json.write(to: url)
            inform(title: "Export complete", message: "Exported \(objects.count) row\(objects.count == 1 ? "" : "s") to \(url.lastPathComponent).")
        } catch {
            appState.openErrorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Backup

    static func backup(appState: AppState) {
        guard let service = appState.service else {
            appState.openErrorMessage = "Open a database first."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Backup Database"
        panel.nameFieldStringValue = service.databaseName + "-backup.db"
        panel.allowedContentTypes = [UTType(filenameExtension: "db") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var dest = url
        if dest.pathExtension.lowercased() != "db" { dest.appendPathExtension("db") }
        if FileManager.default.fileExists(atPath: dest.path) {
            appState.openErrorMessage = "A file already exists at \(dest.lastPathComponent). Choose another name."
            return
        }
        // VACUUM INTO writes a clean, consistent copy of the live database.
        let escaped = dest.path.replacingOccurrences(of: "'", with: "''")
        do {
            _ = try service.runSQL("VACUUM INTO '\(escaped)'")
            inform(title: "Backup complete", message: "Saved a backup to \(dest.lastPathComponent).")
        } catch {
            appState.openErrorMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private static func exportableData(appState: AppState) -> (columns: [String], rows: [[String]], defaultName: String)? {
        guard let service = appState.service else { return nil }
        if let table = appState.currentTableName {
            guard let schema = try? service.schema(for: table),
                  let result = try? service.fetchRows(in: table, state: GridState(limit: 1_000_000)) else {
                return nil
            }
            let cols = schema.columns.map { $0.name }
            let rows = result.rows.map { row in cols.map { (row.values[$0] ?? .null).displayText } }
            return (cols, rows, table)
        }
        if let r = appState.queryViewModel?.result, r.isDataQuery {
            let rows = r.rows.map { row in r.columns.map { (row.values[$0] ?? .null).displayText } }
            return (r.columns, rows, "query_results")
        }
        return nil
    }

    private static func makeTable(headers: [String], rows: [[String]], baseName: String, appState: AppState) throws -> (String, Int) {
        guard let service = appState.service else {
            throw DataTransferError("No database is open.")
        }
        var used = Set<String>()
        let columns: [DesignerColumn] = headers.enumerated().map { index, header in
            var name = sanitize(header)
            if name.isEmpty { name = "col\(index + 1)" }
            var unique = name
            var suffix = 2
            while used.contains(unique.lowercased()) {
                unique = "\(name)_\(suffix)"
                suffix += 1
            }
            used.insert(unique.lowercased())
            return DesignerColumn(name: unique, type: .text)
        }
        let table = uniqueName(baseName, service: service)
        try service.createTable(TableDesign(name: table, columns: columns))
        var inserted = 0
        for row in rows {
            var values: [String: CellValue] = [:]
            for (index, column) in columns.enumerated() {
                let raw = index < row.count ? row[index] : ""
                values[column.name] = CellValue.parse(raw, affinity: .text)
            }
            _ = try service.insertRow(in: table, values: values)
            inserted += 1
        }
        return (table, inserted)
    }

    private static func uniqueName(_ base: String, service: DatabaseService) -> String {
        let existing = Set(((try? service.listObjects()) ?? []).map { $0.name.lowercased() })
        let name = base.isEmpty ? "imported" : base
        if !existing.contains(name.lowercased()) { return name }
        var suffix = 2
        while existing.contains("\(name)_\(suffix)".lowercased()) { suffix += 1 }
        return "\(name)_\(suffix)"
    }

    private static func sanitize(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        out = out.replacingOccurrences(of: "[^A-Za-z0-9_]", with: "_", options: .regularExpression)
        if out.first?.isNumber == true { out = "c" + out }
        return out
    }

    private static func csvText(columns: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append(columns.map(csvEscape).joined(separator: ","))
        for row in rows {
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Minimal RFC-4180 CSV parser: quoted fields, escaped quotes, CRLF/LF.
    private static func parseCSV(_ text: String) -> (headers: [String], rows: [[String]]) {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if inQuotes {
                if char == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == "," {
                row.append(field); field = ""
            } else if char == "\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else if char == "\r" {
                // skip
            } else {
                field.append(char)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        let nonEmpty = rows.filter { $0.contains { !$0.isEmpty } }
        guard let header = nonEmpty.first else { return ([], []) }
        return (header, Array(nonEmpty.dropFirst()))
    }

    private static func jsonObjects(_ object: Any) -> [[String: Any]] {
        if let array = object as? [[String: Any]] { return array }
        if let array = object as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        if let dict = object as? [String: Any] {
            if let rows = dict["rows"] as? [[String: Any]] { return rows }
            if let rows = dict["data"] as? [[String: Any]] { return rows }
            return [dict]
        }
        return []
    }

    private static func jsonScalar(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if value is NSNull { return "" }
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func inform(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct DataTransferError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
