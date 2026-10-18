import SwiftUI
import AppKit
import CelistDBCore

/// Access-style datasheet: grey column headers with sort indicators, a record
/// selector gutter, gridlines, alternating rows, inline editing, and a
/// record-navigation footer with page controls and search.
struct TableGridView: View {
    @ObservedObject var model: TableViewModel
    @State private var editingRowID: Int64?
    @State private var editingColumn: String?
    @State private var editingText: String = ""
    @State private var activeCell: (Int64, String)?
    @FocusState private var cellEditingFocused: Bool

    // Column widths, keyed by column name.
    @State private var widths: [String: CGFloat] = [:]

    private let defaultCellWidth: CGFloat = 140
    private let selectorWidth: CGFloat = 44
    private let rowHeight: CGFloat = 27

    var body: some View {
        VStack(spacing: 0) {
            // Header and rows live in the same horizontal ScrollView so their
            // column positions share the exact same coordinate space and stay
            // perfectly aligned at any width.  Vertical scrolling is handled by
            // a nested ScrollView that only occupies the rows area.
            ScrollView([.horizontal]) {
                VStack(alignment: .leading, spacing: 0, content: rowsContent)
            }
            Divider()
            recordNavigationBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.datasheetBackground)
        .alert("Delete row?", isPresented: deleteConfirmBinding, presenting: model.confirmDeleteRow) { _ in
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.cancelDelete() }
        } message: { _ in
            Text("This will permanently delete the row from the database.")
        }
    }

    /// Builds header + rows as a single VStack inside the horizontal scroll.
    private func rowsContent() -> some View {
        Group {
            if let schema = model.schema {
                headerRow(columns: schema.columns)
            }
            if model.rows.isEmpty {
                emptyState
            } else {
                // Only scroll vertically; the parent handles horizontal scrolling.
                // No maxWidth constraint so the horizontal width is driven purely
                // by the column widths — identical to the header above.
                ScrollView([.vertical]) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                            dataRow(row, index: index)
                        }
                        if model.rows.count < model.totalCount && model.currentPage == model.totalPages - 1 {
                            Button("Load more rows…") { model.loadMoreIfNeeded() }
                                .buttonStyle(.link)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    // MARK: - Header

    private func headerRow(columns: [SchemaColumn]) -> some View {
        HStack(spacing: 0) {
            // Record-selector header cell
            VStack(spacing: 0) {
                Image(systemName: "arrowtriangle.down.square")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0x5A5A5A))
            }
            .frame(width: selectorWidth, height: 28)
            .background(headerFill)
            .overlay(alignment: .trailing) { Divider().overlay(AccessTheme.gridLine) }

            ForEach(columns) { col in
                headerCell(col)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerFill: some View {
        LinearGradient(
            colors: [AccessTheme.headerBackgroundTop, AccessTheme.headerBackgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func headerCell(_ col: SchemaColumn) -> some View {
        let sorted = model.sortIndicator(for: col.name)
        return HStack(spacing: 4) {
            Text(col.name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AccessTheme.headerText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !sorted.isEmpty {
                Text(sorted)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(AccessTheme.appAccent)
            }
        }
        .padding(.leading, 8)
        .frame(width: effectiveWidth(for: col.name), height: 28, alignment: .leading)
        .background(headerFill)
        .overlay(alignment: .trailing) { Divider().overlay(AccessTheme.gridLine) }
        .contentShape(Rectangle())
        .onTapGesture { model.toggleSort(column: col.name) }
        .onHover { hovering in
            headerHovered = hovering ? col.name : nil
        }
        .overlay {
            if headerHovered == col.name {
                Color.white.opacity(0.22)
            }
        }
        .help(col.type.isEmpty ? "\(col.name) · no declared type — click to sort" : "\(col.name) · \(col.type) — click to sort")
    }

    @State private var headerHovered: String?

    // MARK: - Rows

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.totalCount == 0 ? "tray" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(model.totalCount == 0 ? "There are no records in this table yet." : "No records match your search.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if model.totalCount == 0 && !model.isView {
                Button("Add a record") { model.addRow() }
                    .buttonStyle(.borderedProminent)
            }
            if model.isView {
                Text("Views are read-only.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func dataRow(_ row: DataRow, index: Int) -> some View {
        let isSelected = model.selectedRowID == row.rowID
        let alternate = index % 2 == 1
        let rowBackground: Color = isSelected ? AccessTheme.rowHighlight : (alternate ? AccessTheme.alternateRow : AccessTheme.datasheetBackground)

        return HStack(spacing: 0) {
            // Record selector gutter
            VStack(spacing: 0) {
                if isSelected {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(AccessTheme.recordIndicator)
                        .rotationEffect(.degrees(90))
                }
            }
            .frame(width: selectorWidth, height: rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { select(row) }
            .background(rowBackground)
            .overlay(alignment: .trailing) { Divider().overlay(AccessTheme.gridLine) }

            ForEach(model.columns) { col in
                cell(for: col, in: row, isSelected: isSelected)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func select(_ row: DataRow) {
        model.selectedRowID = row.rowID
    }

    // MARK: - Cells

    private func cell(for col: SchemaColumn, in row: DataRow, isSelected: Bool) -> some View {
        let value = row.values[col.name] ?? .null
        let isEditing = editingRowID == row.rowID && editingColumn == col.name
        let isActive = activeCell?.0 == row.rowID && activeCell?.1 == col.name

        return ZStack {
            if isEditing {
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($cellEditingFocused)
                    .onSubmit { commitEdit(row: row, column: col.name) }
                    .onExitCommand { cancelEdit() }
                    .onAppear {
                        editingText = value.displayText
                        cellEditingFocused = true
                    }
                    .padding(.horizontal, 5)
                    .offset(x: -4)
            } else {
                HStack(spacing: 0) {
                    if value == .null {
                        Text("(no value)")
                            .font(.system(size: 11))
                            .foregroundStyle(AccessTheme.nullText)
                            .italic()
                    } else {
                        Text(value.displayText)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .foregroundStyle(value == .null ? AccessTheme.nullText : color(for: col))
                            .frame(maxWidth: .infinity, alignment: alignment(for: col))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    select(row)
                    activeCell = (row.rowID, col.name)
                    model.selectedColumn = col.name
                    if !model.isView {
                        beginEdit(row: row, column: col.name)
                    }
                }
            }
        }
        .frame(width: effectiveWidth(for: col.name), height: rowHeight, alignment: .leading)
        .padding(.leading, 8)
        .background(cellBackground(isSelected: isSelected, isActive: isActive))
        .overlay(alignment: .trailing) { Divider().overlay(AccessTheme.gridLine) }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isActive ? AccessTheme.cellHighlightBorder : Color.clear, lineWidth: 1.5)
                .padding(0.5)
        )
        .onAppear { if row.rowID == editingRowID && editingColumn == col.name {} }
    }

    private func cellBackground(isSelected: Bool, isActive: Bool) -> Color {
        if isActive { return AccessTheme.cellHighlight }
        if isSelected { return AccessTheme.rowHighlight }
        return Color.clear
    }

    // MARK: - Editing

    private func beginEdit(row: DataRow, column: String) {
        editingRowID = row.rowID
        editingColumn = column
        editingText = (row.values[column] ?? .null).displayText
    }

    private func commitEdit(row: DataRow, column: String) {
        let affinity = model.affinity(for: column)
        let value = CellValue.parse(editingText, affinity: affinity)
        model.commitEdit(value, column: column, rowID: row.rowID)
        editingRowID = nil
        editingColumn = nil
    }

    private func cancelEdit() {
        editingRowID = nil
        editingColumn = nil
    }

    // MARK: - Record navigation

    private var recordNavigationBar: some View {
        HStack(spacing: 6) {
            if !model.isView {
                Button {
                    model.addRow()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("New")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 3).fill(AccessTheme.appAccent))
                .help("Add a new record")
            }

            Text("Record:")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x444444))

            navButton("chevron.left.to.line", help: "First record") { model.goToPage(0) }
                .disabled(model.currentPage <= 0)
            navButton("chevron.left", help: "Previous record") { model.movePage(by: -1) }
                .disabled(model.currentPage <= 0)

            Text("\(model.selectedRowID != nil ? displayRecordNumber : model.rows.isEmpty ? 0 : model.loadedOffset + 1) of \(model.totalCount)")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x444444))
                .monospacedDigit()

            navButton("chevron.right", help: "Next record") { model.movePage(by: 1) }
                .disabled(model.currentPage >= model.totalPages - 1)
            navButton("chevron.right.to.line", help: "Last record") { model.goToPage(model.totalPages - 1) }
                .disabled(model.currentPage >= model.totalPages - 1)

            Rectangle().fill(AccessTheme.gridLine).frame(width: 1, height: 16).padding(.horizontal, 6)

            if let status = model.statusMessage {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x1E7B34))
            }

            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(AccessTheme.statusBarText)
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 160)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(AccessTheme.fieldBorder))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AccessTheme.statusBar)
    }

    private var displayRecordNumber: Int {
        guard model.loadedOffset >= 0 else { return 1 }
        return model.loadedOffset + (model.rows.firstIndex(where: { $0.rowID == model.selectedRowID }) ?? 0) + 1
    }

    private func navButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AccessTheme.navItemText)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(AccessTheme.fieldBorder))
        )
        .help(help)
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { model.confirmDeleteRow != nil },
            set: { if !$0 { model.cancelDelete() } }
        )
    }

    // MARK: - Styling helpers

    private func effectiveWidth(for column: String) -> CGFloat {
        widths[column] ?? defaultCellWidth
    }

    private func alignment(for col: SchemaColumn) -> Alignment {
        switch col.affinity {
        case .integer, .real, .boolean:
            return .trailing
        default:
            return .leading
        }
    }

    private func color(for col: SchemaColumn) -> Color {
        switch col.affinity {
        case .boolean: return AccessTheme.accessBlueDark
        default: return AccessTheme.cellText
        }
    }
}