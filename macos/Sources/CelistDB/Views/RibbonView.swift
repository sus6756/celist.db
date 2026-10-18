import SwiftUI
import AppKit
import CelistDBCore

/// The tabs shown on the Office-style ribbon.
enum RibbonTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case create = "Create"
    case externalData = "External Data"
    case databaseTools = "Database Tools"
    case file = "File"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .create: return "plus.square.on.square"
        case .externalData: return "arrow.down.circle"
        case .databaseTools: return "wrench.and.screwdriver"
        case .file: return "filemenu.and.selection"
        }
    }
}

/// Office-style ribbon: a maroon application strip, a tab strip, and a
/// command area with labelled groups. Recreates the Microsoft Access look.
struct RibbonView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: SidebarSelection?
    @State private var showingRelationships = false

    private static let appStripHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            appStrip
            tabStrip
            groupArea
        }
        .sheet(isPresented: $showingRelationships) {
            RelationshipsSheet(rows: relationshipRows())
        }
    }

    // MARK: - Application strip (dark maroon, "Colorful" theme)

    private var appStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("celist.db")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Divider()
                .frame(height: 16)
                .overlay(Color.white.opacity(0.35))

            // Quick Access-style toolbar
            QATButton(systemName: "folder", help: "Open…") { AppActions.openDatabase(appState: appState) }
            QATButton(systemName: "doc.badge.plus", help: "Create database…") { AppActions.newDatabase(appState: appState) }

            Spacer()

            if let db = appState.service?.databaseName {
                Text(db)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.appStripHeight)
        .frame(maxWidth: .infinity)
        .background(AccessGradient(top: AccessTheme.ribbonAppStripTop, bottom: AccessTheme.ribbonAppStripBottom))
    }

    private func QATButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Circle().fill(Color.white.opacity(0.12)))
        .help(help)
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(RibbonTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .background(AccessTheme.ribbonTabBar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.ribbonSeparator).frame(height: 1)
        }
    }

    private func tabButton(_ tab: RibbonTab) -> some View {
        let isSelected = appState.activeRibbonTab == tab
        return Button {
            appState.activeRibbonTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AccessTheme.appAccentDark : Color(hex: 0x3B3B3B))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white : Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(AccessTheme.appAccent)
                    .frame(height: 2)
            }
        }
        .onHover { hovering in
            if hovering && !isSelected {
                // handled by background below via state-free hover is awkward; keep simple
            }
        }
    }

    // MARK: - Command groups

    @ViewBuilder
    private var groupArea: some View {
        switch appState.activeRibbonTab {
        case .home: homeGroups
        case .create: createGroups
        case .externalData: externalDataGroups
        case .databaseTools: databaseToolsGroups
        case .file: fileGroups
        }
    }

    private var homeGroups: some View {
        HStack(alignment: .top, spacing: 0) {
            let vm = appState.currentTable()

            Group {
                ribbonGroup("Records") {
                    let editable = vm != nil && vm?.isView == false
                    RibbonButton(icon: "plus", label: "New", help: vm?.isView == true ? "Views are read-only" : "Add a new record", enabled: editable) {
                        vm?.addRow()
                    }
                    RibbonButton(icon: "square.on.square", label: "Duplicate", help: "Duplicate the selected record", enabled: editable && appState.currentSelectedRowID != nil) {
                        guard let vm else { return }
                        if let r = vm.rows.first(where: { $0.rowID == vm.selectedRowID }) {
                            vm.duplicateRow(r)
                        }
                    }
                    RibbonButton(icon: "trash", label: "Delete", help: "Delete the selected record", enabled: editable && appState.currentSelectedRowID != nil) {
                        vm?.requestDelete()
                    }
                    RibbonButton(icon: "arrow.clockwise", label: "Refresh", help: "Reload the datasheet", enabled: vm != nil) {
                        vm?.reload()
                    }
                }
            }

            Divider().frame(height: 96).overlay(AccessTheme.ribbonSeparator).padding(.horizontal, 4)

            Group {
                ribbonGroup("Sort & Filter") {
                    RibbonButton(icon: "arrow.up", label: "Ascending", help: "Sort the current column A→Z", enabled: vm != nil) {
                        vm?.ribbonSortColumn(ascending: true)
                    }
                    RibbonButton(icon: "arrow.down", label: "Descending", help: "Sort the current column Z→A", enabled: vm != nil) {
                        vm?.ribbonSortColumn(ascending: false)
                    }
                    RibbonButton(icon: "line.3.horizontal.decrease.circle", label: "Clear Filter", help: "Remove any search filter", enabled: (vm?.searchText.isEmpty == false) || vm?.sortColumn != nil) {
                        vm?.clearFilterAndSort()
                    }
                }
            }

            Divider().frame(height: 96).overlay(AccessTheme.ribbonSeparator).padding(.horizontal, 4)

            Group {
                ribbonGroup("Search") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            TextField("Find in datasheet…", text: searchBinding)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 8)
                        .frame(width: 200, height: 26)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AccessTheme.fieldBorder))
                        .disabled(vm == nil)

                        Text(vm == nil ? "Open a table to search" : "Filter all columns live")
                            .font(.system(size: 10))
                            .foregroundStyle(AccessTheme.ribbonGroupCaption)
                    }
                    .padding(.top, 10)
                    .frame(width: 208, height: 66)
                }
            }

            Spacer()
        }
        .padding(.top, 8)
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .background(AccessTheme.ribbonGroupArea)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.ribbonSeparator).frame(height: 1)
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { appState.currentTable()?.searchText ?? "" },
            set: { newValue in appState.currentTable()?.searchText = newValue }
        )
    }

    private var createGroups: some View {
        HStack(alignment: .top, spacing: 0) {
            ribbonGroup("Tables") {
                RibbonButton(icon: "tablecells.badge.plus", label: "Table", help: "Design a new table") {
                    selection = .newTable
                }
                RibbonButton(icon: "sparkles", label: "Sample DB", help: "Create the sample shop database") {
                    AppActions.createSample(appState: appState)
                }
            }

            Divider().frame(height: 96).overlay(AccessTheme.ribbonSeparator).padding(.horizontal, 4)

            ribbonGroup("Queries") {
                RibbonButton(icon: "terminal", label: "SQL Query", help: "Open the raw SQL editor") {
                    selection = .query
                }
            }

            Spacer()
        }
        .padding(.top, 8)
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .background(AccessTheme.ribbonGroupArea)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.ribbonSeparator).frame(height: 1)
        }
    }

    private var externalDataGroups: some View {
        HStack(alignment: .top, spacing: 0) {
            ribbonGroup("Import & Link") {
                RibbonButton(icon: "arrow.down.doc", label: "CSV Import", help: "Import a CSV file as a new table", enabled: appState.isOpen) {
                    ExternalDataActions.importCSV(appState: appState)
                }
                RibbonButton(icon: "arrow.down.doc.fill", label: "JSON Import", help: "Import a JSON file as a new table", enabled: appState.isOpen) {
                    ExternalDataActions.importJSON(appState: appState)
                }
            }
            Divider().frame(height: 96).overlay(AccessTheme.ribbonSeparator).padding(.horizontal, 4)
            ribbonGroup("Export") {
                RibbonButton(icon: "arrow.up.doc", label: "CSV Export", help: "Export the current table or query result as CSV", enabled: appState.isOpen) {
                    ExternalDataActions.exportSpreadsheet(appState: appState, title: "Export CSV")
                }
                RibbonButton(icon: "arrow.up.doc.fill", label: "Excel Export", help: "Export a spreadsheet (CSV) that Excel opens", enabled: appState.isOpen) {
                    ExternalDataActions.exportSpreadsheet(appState: appState, title: "Export for Excel")
                }
                RibbonButton(icon: "curlybraces", label: "JSON Export", help: "Export the current table or query result as JSON", enabled: appState.isOpen) {
                    ExternalDataActions.exportJSON(appState: appState)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .background(AccessTheme.ribbonGroupArea)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.ribbonSeparator).frame(height: 1)
        }
    }

    private var databaseToolsGroups: some View {
        HStack(alignment: .top, spacing: 0) {
            ribbonGroup("Tools") {
                RibbonButton(icon: "link", label: "Relationships", help: "Show the foreign-key relationships between tables", enabled: appState.isOpen) {
                    showingRelationships = true
                }
                RibbonButton(icon: "doc.on.doc", label: "Backup DB", help: "Save a backup copy of this database", enabled: appState.isOpen) {
                    ExternalDataActions.backup(appState: appState)
                }
            }
            Spacer()
        }
        .padding(.top, 8)
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .background(AccessTheme.ribbonGroupArea)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.ribbonSeparator).frame(height: 1)
        }
    }

    /// Collects every foreign key across the database for the Relationships sheet.
    private func relationshipRows() -> [RelationshipRow] {
        guard let service = appState.service, let objects = try? service.listObjects() else { return [] }
        var rows: [RelationshipRow] = []
        for object in objects where object.kind == .table {
            guard let schema = try? service.schema(for: object.name) else { continue }
            for fk in schema.foreignKeys {
                let dest = fk.destinationColumns.isEmpty ? "—" : fk.destinationColumns.joined(separator: ", ")
                for origin in fk.originColumns {
                    rows.append(RelationshipRow(fromTable: object.name, fromColumn: origin, toTable: fk.destinationTable, toColumn: dest))
                }
            }
        }
        return rows
    }

    private var fileGroups: some View {
        HStack(alignment: .top, spacing: 0) {
            ribbonGroup("Database") {
                RibbonButton(icon: "folder", label: "Open…", help: "Open an existing database") {
                    AppActions.openDatabase(appState: appState)
                }
                RibbonButton(icon: "doc.badge.plus", label: "New…", help: "Create a new database") {
                    AppActions.newDatabase(appState: appState)
                }
            }
            Divider().frame(height: 96).overlay(AccessTheme.ribbonSeparator).padding(.horizontal, 4)
            ribbonGroup("Support") {
                RibbonButton(icon: "info.circle", label: "About", help: "About celist.db") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                RibbonButton(icon: "xmark.circle", label: "Close DB", help: "Close the current database", enabled: appState.isOpen) {
                    appState.close()
                }
            }
            Spacer()
        }
        .padding(.top, 8)
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .background(AccessTheme.ribbonGroupArea)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.ribbonSeparator).frame(height: 1)
        }
    }

    // MARK: - Group chrome

    private func ribbonGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                content()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AccessTheme.ribbonGroupCaption)
                .lineLimit(1)
                .padding(.top, 6)
                .padding(.bottom, 5)
                .padding(.horizontal, 10)
        }
    }
}

/// A single square ribbon command button with icon + caption.
struct RibbonButton: View {
    let icon: String
    let label: String
    var help: String = ""
    var enabled = true
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 34)
                    .foregroundStyle(enabled ? AccessTheme.appAccentDark : Color(hex: 0xB0B0B0))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(enabled ? AccessTheme.cellText : Color(hex: 0xB0B0B0))
                    .lineLimit(1)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
            .frame(width: 58)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        pressed ? AccessTheme.ribbonButtonActive
                        : hovering ? AccessTheme.ribbonButtonHover
                        : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        hovering || pressed ? AccessTheme.ribbonButtonBorder : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

/// Access-like "Relationships" window: lists every foreign key in the database.
struct RelationshipsSheet: View {
    let rows: [RelationshipRow]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Relationships", systemImage: "link")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(rows.count) link\(rows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()

            if rows.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 38))
                        .foregroundStyle(.tertiary)
                    Text("No foreign-key relationships have been defined.")
                        .foregroundStyle(.secondary)
                    Text("Tip: add a “References” target to a column in the Table Designer.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                        GridRow {
                            Text("Table").bold()
                            Text("Column").bold()
                            Text("").bold()
                            Text("References").bold()
                            Text("Column").bold()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(rows) { row in
                            GridRow {
                                Text(row.fromTable)
                                Text(row.fromColumn)
                                Text("→").foregroundStyle(AccessTheme.appAccent)
                                Text(row.toTable)
                                Text(row.toColumn)
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(AccessTheme.datasheetBackground)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AccessTheme.fieldBorder))
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 640, height: 460)
        .background(AccessTheme.windowBackground)
    }
}