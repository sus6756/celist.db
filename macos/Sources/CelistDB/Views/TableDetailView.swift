import SwiftUI
import AppKit
import CelistDBCore

/// Wraps a table with an Access-style document tab header plus the
/// Data / Design / SQL sub-views for the selected object.
struct TableDetailView: View {
    @ObservedObject var model: TableViewModel
    @EnvironmentObject var appState: AppState
    @State private var tab: ObjectTab = .data

    enum ObjectTab: String, CaseIterable, Identifiable {
        case data = "Data"
        case design = "Design"
        case sql = "SQL"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabHeader
            Divider()
            switch tab {
            case .data:
                TableGridView(model: model)
            case .design:
                DesignTab(model: model)
            case .sql:
                SQLTab(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.datasheetBackground)
    }

    /// The opened object presented as an Access "tabbed document".
    private var tabHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: model.schema?.isView == true ? "rectangle.split.2x2" : "tablecells")
                .font(.system(size: 12))
                .foregroundStyle(AccessTheme.appAccentDark)
            Text(model.tableName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1F1F1F))
            Picker("", selection: $tab) {
                ForEach(ObjectTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .help("Switch between datasheet, structure, and the object's SQL.")

            Spacer()
            if let schema = model.schema {
                Text("\(schema.columns.count) field\(schema.columns.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 34)
        .background(AccessTheme.tabActive)
        .overlay(alignment: .leading) {
            Rectangle().fill(AccessTheme.tabUnderline).frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.statusBarBorder).frame(height: 1)
        }
    }
}

/// Read-only structure view: columns, types, keys, defaults and foreign keys.
private struct DesignTab: View {
    @ObservedObject var model: TableViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let schema = model.schema {
                    if schema.isView {
                        Label("Views are read-only; their structure comes from the underlying query.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            header("Name"); header("Type"); header("Key")
                            header("Required"); header("Default"); header("References")
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(schema.columns) { col in
                            GridRow {
                                Text(col.name).font(.system(size: 12, weight: .medium))
                                Text(col.type.isEmpty ? "(none)" : col.type).font(.system(size: 12))
                                badges(for: col, schema: schema)
                                Text(col.isNotNull ? "NOT NULL" : "—")
                                    .font(.system(size: 11))
                                    .foregroundStyle(col.isNotNull ? Color.primary : .secondary)
                                Text(col.defaultValueSQL ?? "—")
                                    .font(.custom("Menlo", size: 11))
                                    .foregroundStyle(col.defaultValueSQL == nil ? .secondary : .primary)
                                Text(reference(for: col, schema: schema))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !schema.indexes.isEmpty {
                        Text("Indexes")
                            .font(.caption.weight(.semibold))
                        ForEach(schema.indexes) { idx in
                            Text("\(idx.name) — \(idx.isUnique ? "UNIQUE" : "INDEX") (\(idx.columns.joined(separator: ", ")))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No schema information available.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AccessTheme.datasheetBackground)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(.secondary)
    }

    private func badges(for col: SchemaColumn, schema: TableSchema) -> some View {
        HStack(spacing: 4) {
            if schema.primaryKeyColumns.contains(col.name) {
                badge("PK", color: AccessTheme.appAccentDark)
                if schema.primaryKeyColumns.count > 1 {
                    badge("#\(col.primaryKeyIndex)", color: .secondary)
                }
            } else {
                Text("—").foregroundStyle(.secondary).font(.system(size: 11))
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(color))
    }

    private func reference(for col: SchemaColumn, schema: TableSchema) -> String {
        for fk in schema.foreignKeys where fk.originColumns.contains(col.name) {
            let dest = zip(fk.originColumns, fk.destinationColumns)
            if let pair = dest.first(where: { $0.0 == col.name }) {
                return "\(fk.destinationTable).\(pair.1)"
            }
            return fk.destinationTable
        }
        return "—"
    }
}

/// Read-only view of the object's original CREATE statement.
private struct SQLTab: View {
    @ObservedObject var model: TableViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("\(model.isView ? "Resource" : "Create") SQL", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    if let sql = model.createSQL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sql, forType: .string)
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(model.createSQL == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(AccessTheme.gridLine)

            ScrollView {
                if let sql = model.createSQL {
                    Text(SQLAttributed(sql, dark: false).attributed)
                        .font(.custom("Menlo", size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                } else {
                    Text("No SQL is recorded for this object.")
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .background(AccessTheme.datasheetBackground)
        }
    }
}
