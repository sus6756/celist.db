import SwiftUI
import AppKit
import CelistDBCore

/// Visual, point-and-click table designer with live SQL preview and
/// data-type suggestions derived from column names.
struct TableDesignerView: View {
    @ObservedObject var model: TableDesignerViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                nameField

                columnsSection

                previewSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.windowBackground)
        .alert("Table created", isPresented: successAlertBinding) {
            Button("Done") {}
        } message: {
            Text(model.successMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Design a Table")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x1F1F1F))
            Text("Point-and-click — no SQL required. We generate the SQL for you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Table name", systemImage: "character.cursor.ibeam")
                .font(.caption.weight(.semibold))
            TextField("e.g. customers", text: $model.tableName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
        }
    }

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Columns", systemImage: "tablecells")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    model.startWithSampleColumns()
                } label: {
                    Label("Sample columns", systemImage: "wand.and.stars")
                }
                .help("Adds a few sensible example columns so you can see how it works.")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    headerCell("Name", width: 150)
                    headerCell("Type", width: 150)
                    headerCell("Primary", width: 60)
                    headerCell("Auto", width: 60)
                    headerCell("Not null", width: 70)
                    headerCell("Unique", width: 70)
                    headerCell("Default", width: 120)
                    headerCell("References", width: 170)
                    Color.clear.frame(width: 30, height: 0)
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)

                ForEach(model.columns) { col in
                    columnRow(col)
                }
            }

            if model.columns.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "plus.square.dashed")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No columns yet — add your first one.")
                            .foregroundStyle(.secondary)
                        Button("Add Column") { model.addColumn() }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .padding(.vertical, 24)
            } else {
                HStack {
                    Button {
                        model.addColumn()
                    } label: {
                        Label("Add Column", systemImage: "plus")
                    }
                    Text("Tip: type a column name like “email” or “price” and we suggest the right type.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccessTheme.fieldBorder))
    }

    private func columnRow(_ col: DesignerColumn) -> some View {
        GridRow {
            textField(for: col)
            typePicker(for: col)
            primaryToggle(for: col)
            autoToggle(for: col)
            notNullToggle(for: col)
            uniqueToggle(for: col)
            defaultField(for: col)
            fkPicker(for: col)
            removeButton(for: col)
        }
    }

    // MARK: - Cell editors

    private func textField(for col: DesignerColumn) -> some View {
        TextField("col_name", text: binding(for: \.name, col: col))
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
    }

    private func typePicker(for col: DesignerColumn) -> some View {
        Menu {
            Button("Suggest from name") { suggestType(for: col) }
            Divider()
            ForEach(SQLiteType.allCases) { type in
                Button(type.displayName) { setType(type, for: col) }
            }
        } label: {
            HStack {
                Text(col.type.displayName)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 12))
            .frame(width: 150, height: 22)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AccessTheme.fieldBorder))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 150)
        .help("Click to choose a data type, or auto-suggest one from the column name.")
    }

    private func primaryToggle(for col: DesignerColumn) -> some View {
        Toggle("", isOn: Binding(
            get: { col.isPrimaryKey },
            set: { setPK($0, for: col) }
        ))
        .toggleStyle(.checkbox)
        .frame(width: 60)
        .help("Make this column the primary key (uniquely identifies each row).")
    }

    private func autoToggle(for col: DesignerColumn) -> some View {
        Toggle("", isOn: Binding(
            get: { col.isAutoIncrement },
            set: { setAuto($0, for: col) }
        ))
        .toggleStyle(.checkbox)
        .disabled(!(col.isPrimaryKey && col.type == .integer))
        .frame(width: 60)
        .help("Automatically number each new row (only for an integer primary key).")
    }

    private func notNullToggle(for col: DesignerColumn) -> some View {
        Toggle("", isOn: binding(for: \.isNotNull, col: col))
            .toggleStyle(.checkbox)
            .frame(width: 70)
            .help("Forbid empty values in this column.")
    }

    private func uniqueToggle(for col: DesignerColumn) -> some View {
        Toggle("", isOn: binding(for: \.isUnique, col: col))
            .toggleStyle(.checkbox)
            .frame(width: 70)
            .help("Ensure every value in this column is different.")
    }

    private func defaultField(for col: DesignerColumn) -> some View {
        TextField("(none)", text: binding(for: \.defaultValue, col: col))
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
            .help("A value inserted automatically when a row is created (SQL literal).")
    }

    private func fkPicker(for col: DesignerColumn) -> some View {
        Menu {
            Button("(none — not a foreign key)") { clearFK(for: col) }
            Divider()
            ForEach(model.foreignKeyTargets) { target in
                Button("\(target.table).\(target.column)") {
                    setFK(target, for: col)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(col.foreignKey.map { "\($0.table).\($0.column)" } ?? "none")
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .frame(width: 170, height: 22, alignment: .leading)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AccessTheme.fieldBorder))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 170)
        .help("Link this column to another table's key (a foreign key).")
    }

    private func removeButton(for col: DesignerColumn) -> some View {
        Button {
            model.removeColumn(col)
        } label: {
            Image(systemName: "minus.circle")
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .help("Remove this column.")
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    // MARK: - Designer functions

    private func suggestType(for col: DesignerColumn) {
        setType(SQLiteType.suggested(for: col.name), for: col)
    }

    private func setType(_ type: SQLiteType, for col: DesignerColumn) {
        if let i = model.columns.firstIndex(where: { $0.id == col.id }) {
            if type != .integer { model.columns[i].isAutoIncrement = false }
            model.columns[i].type = type
        }
    }

    private func setPK(_ on: Bool, for col: DesignerColumn) {
        if let i = model.columns.firstIndex(where: { $0.id == col.id }) {
            model.columns[i].isPrimaryKey = on
            if !on { model.columns[i].isAutoIncrement = false }
        }
    }

    private func setAuto(_ on: Bool, for col: DesignerColumn) {
        if let i = model.columns.firstIndex(where: { $0.id == col.id }) {
            model.columns[i].isAutoIncrement = on
        }
    }

    private func setFK(_ fk: ForeignKeyRef, for col: DesignerColumn) {
        if let i = model.columns.firstIndex(where: { $0.id == col.id }) {
            model.columns[i].foreignKey = fk
        }
    }

    private func clearFK(for col: DesignerColumn) {
        if let i = model.columns.firstIndex(where: { $0.id == col.id }) {
            model.columns[i].foreignKey = nil
        }
    }

    private func binding(for keyPath: WritableKeyPath<DesignerColumn, String>, col: DesignerColumn) -> Binding<String> {
        let id = col.id
        return Binding(
            get: {
                if let i = model.columns.firstIndex(where: { $0.id == id }) {
                    return model.columns[i][keyPath: keyPath]
                }
                return ""
            },
            set: { newValue in
                if let i = model.columns.firstIndex(where: { $0.id == id }) {
                    model.columns[i][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func binding(for keyPath: WritableKeyPath<DesignerColumn, Bool>, col: DesignerColumn) -> Binding<Bool> {
        let id = col.id
        return Binding(
            get: {
                if let i = model.columns.firstIndex(where: { $0.id == id }) {
                    return model.columns[i][keyPath: keyPath]
                }
                return false
            },
            set: { newValue in
                if let i = model.columns.firstIndex(where: { $0.id == id }) {
                    model.columns[i][keyPath: keyPath] = newValue
                }
            }
        )
    }

    // MARK: - Preview + save

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("SQL preview", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let msg = model.successMessage {
                    Text(msg).font(.footnote).foregroundStyle(.green)
                }
                if let err = model.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }
            ScrollView(.vertical) {
                Text(SQLAttributed(model.previewSQL, dark: false).attributed)
                    .font(.custom("Menlo", size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxHeight: 180)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AccessTheme.fieldBorder))

            HStack {
                Spacer()
                Button("Clear") { model.reset() }
                Button("Create Table") { model.save() }
                    .buttonStyle(AccessProminentButtonStyle())
                    .disabled(model.columns.isEmpty || model.tableName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AccessTheme.fieldBorder))
    }

    private var successAlertBinding: Binding<Bool> {
        Binding(
            get: { !(model.successMessage ?? "").isEmpty },
            set: { if !$0 { model.successMessage = nil } }
        )
    }
}