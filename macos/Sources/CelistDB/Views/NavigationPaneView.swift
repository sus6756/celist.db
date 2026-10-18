import SwiftUI
import AppKit
import CelistDBCore

/// Access-style navigation pane: a blue gradient header bar, collapsible
/// object groups, and hover/selection highlighting.
struct NavigationPaneView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: SidebarSelection?
    @State private var objects: [SchemaObject] = []
    @State private var rowCounts: [String: Int64] = [:]
    @State private var tablesCollapsed = false
    @State private var viewsCollapsed = false
    @State private var hoveredItem: SidebarSelection?

    var body: some View {
        VStack(spacing: 0) {
            header
            scrollArea
        }
        .frame(minWidth: 230, idealWidth: 250, maxWidth: 320)
        .background(AccessTheme.navPaneBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AccessTheme.navPaneBorder).frame(width: 1)
        }
        .onAppear { reload() }
        .onChange(of: appState.dbGeneration) {
            reload()
            // Only drop the selection if the selected object disappeared.
            // Keeping e.g. `.newTable` selected lets the designer stay on
            // screen (and show its "table created" confirmation) after a DDL
            // change bumps the generation.
            if case .table(let name) = selection,
               !objects.contains(where: { $0.name == name }) {
                selection = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "building.columns")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Text("All Access Objects")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Menu {
                Button("Refresh", action: reload)
                Button("Create Sample Database…") { AppActions.createSample(appState: appState) }
                Divider()
                Button("Open…") { AppActions.openDatabase(appState: appState) }
                Button("Close Database", action: { appState.close() })
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .background(Circle().fill(Color.black.opacity(0.15)))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(AccessGradient(top: AccessTheme.navHeaderGradientTop, bottom: AccessTheme.navHeaderGradientBottom))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.navPaneBorder).frame(height: 1)
        }
    }

    // MARK: - Items

    private var scrollArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                actionItems

                if !tables.isEmpty {
                    groupHeader(title: "Tables", count: tables.count, collapsed: $tablesCollapsed)
                    if !tablesCollapsed {
                        ForEach(tables) { tableItem($0) }
                    }
                }

                if !views.isEmpty {
                    groupHeader(title: "Views", count: views.count, collapsed: $viewsCollapsed)
                    if !viewsCollapsed {
                        ForEach(views) { tableItem($0, isView: true) }
                    }
                }

                if objects.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 24)
                        Image(systemName: "externaldrive")
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text("This database is empty.\nCreate a table to get started.")
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var actionItems: some View {
        VStack(spacing: 0) {
            accessItem(
                icon: "plus.square.dashed",
                title: "New Table",
                subtitle: "Design a table",
                tag: .newTable,
                isAction: true
            )
            accessItem(
                icon: "terminal",
                title: "SQL Query",
                subtitle: "Raw SQL editor",
                tag: .query,
                isAction: true
            )
            Rectangle().fill(AccessTheme.gridLine).frame(height: 1).padding(.horizontal, 10)
        }
        .padding(.bottom, 4)
    }

    private func accessItem(
        icon: String,
        title: String,
        subtitle: String,
        tag: SidebarSelection,
        isAction: Bool
    ) -> some View {
        let isSelected = selection == tag
        return Button {
            selection = tag
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AccessTheme.navItemSelectedText : AccessTheme.appAccentDark)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AccessTheme.navItemSelectedText : AccessTheme.navItemText)
                        .lineLimit(1)
                    if isAction {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.leading, 12)
            .frame(height: isAction ? 34 : 28)
            .contentShape(Rectangle())
            .background(isSelected ? AccessTheme.navItemSelected : (hoveredItem == tag ? AccessTheme.navItemHover : Color.clear))
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(AccessTheme.accessBlue).frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? tag : nil
        }
    }

    private func tableItem(_ object: SchemaObject, isView: Bool = false) -> some View {
        let tag = SidebarSelection.table(object.name)
        let isSelected = selection == tag
        return Button {
            selection = tag
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isView ? "rectangle.split.2x2" : "tablecells")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? AccessTheme.navItemSelectedText : Color(hex: 0x6E6E6E))
                    .frame(width: 18)
                Text(object.name)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? AccessTheme.navItemSelectedText : AccessTheme.navItemText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !isView, let count = rowCounts[object.name] {
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? AccessTheme.navItemSelectedText.opacity(0.85) : .secondary)
                        .monospacedDigit()
                }
            }
            .padding(.leading, 16)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(isSelected ? AccessTheme.navItemSelected : (hoveredItem == tag ? AccessTheme.navItemHover : Color.clear))
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(AccessTheme.accessBlue).frame(width: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? tag : nil
        }
        .help(isView ? "Open the \(object.name) view" : "Open the \(object.name) table")
    }

    private func groupHeader(title: String, count: Int, collapsed: Binding<Bool>) -> some View {
        Button {
            collapsed.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AccessTheme.ribbonGroupCaption)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AccessTheme.navGroupHeaderText)
                Text("(\(count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(AccessTheme.navPaneBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AccessTheme.gridLine).frame(height: 1).padding(.horizontal, 10)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func reload() {
        guard let service = appState.service else { return }
        do {
            objects = try service.listObjects()
            var counts: [String: Int64] = [:]
            for object in objects where object.kind == .table {
                counts[object.name] = (try? service.rowCount(for: object.name)) ?? 0
            }
            rowCounts = counts
        } catch {
            appState.openErrorMessage = error.localizedDescription
        }
    }

    private var tables: [SchemaObject] { objects.filter { $0.kind == .table } }
    private var views: [SchemaObject] { objects.filter { $0.kind == .view } }
}