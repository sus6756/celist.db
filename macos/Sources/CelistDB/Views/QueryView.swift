import SwiftUI
import AppKit
import CelistDBCore

/// Raw SQL editor with syntax highlighting, live results grid, and
/// persistent query history.
struct QueryView: View {
    @ObservedObject var model: QueryViewModel
    @EnvironmentObject var appState: AppState
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            tabHeader
            Divider()
            HSplitView {
                editorPane
                    .frame(minWidth: 380, idealWidth: 520)
                    .layoutPriority(1)

                resultsPane
                    .frame(minWidth: 300, idealWidth: 460)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.datasheetBackground)
    }

    /// The opened "SQL query" presented as a document tab.
    private var tabHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 12))
                .foregroundStyle(AccessTheme.appAccentDark)
            Text("SQL Query")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1F1F1F))
            Spacer()
            Text("SQL View")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 32)
        .background(AccessTheme.tabActive)
        .overlay(alignment: .leading) {
            Rectangle().fill(AccessTheme.tabUnderline).frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccessTheme.statusBarBorder).frame(height: 1)
        }
    }

    // MARK: - Editor

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("SQL Statement", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Menu {
                    Button("Query history (show latest)", action: { showingHistory = true })
                    Divider()
                    Button("Select all customers") {
                        model.runSample("SELECT * FROM customers LIMIT 50;")
                    }
                    Button("Count per product") {
                        model.runSample("""
                            SELECT p.name, SUM(o.quantity) AS total_sold
                            FROM orders o
                            JOIN products p ON p.id = o.product_id
                            GROUP BY p.name
                            ORDER BY total_sold DESC
                            """)
                    }
                } label: {
                    Label("Samples", systemImage: "lightbulb")
                }
                .help("Insert a sample query to get started.")
                Button("Clear") { model.sql = ""; model.result = nil; model.errorMessage = nil }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(AccessTheme.gridLine)

            SQLTextView(text: $model.sql)
                .frame(minHeight: 160)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first?.makeKeyAndOrderFront(nil)
                    }
                }

            Divider().overlay(AccessTheme.gridLine)

            HStack(spacing: 8) {
                Button {
                    model.run()
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .frame(minWidth: 60)
                }
                .buttonStyle(AccessProminentButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .help("Run the current query (⌘↩).")

                Spacer()

                if model.isRunning {
                    ProgressView().controlSize(.small)
                }

                Button {
                    showingHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .disabled(model.history.isEmpty)
                .help("Show your recent queries.")
            }
            .padding(10)

            Divider().overlay(AccessTheme.gridLine)

            statusBar
        }
        .background(AccessTheme.datasheetBackground)
        .sheet(isPresented: $showingHistory) {
            HistorySheet(history: model.history) { entry in
                model.useHistory(entry)
                showingHistory = false
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if let err = model.errorMessage {
                Image(systemName: "xmark.octagon")
                    .foregroundStyle(.red)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let r = model.result {
                if r.isDataQuery {
                    Text("\(r.rows.count) row\(r.rows.count == 1 ? "" : "s") returned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Done — \(r.rowCount) row\(r.rowCount == 1 ? "" : "s") affected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Run a query to see results. Tip: ⌘↩ to run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Results

    private var resultsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Results", systemImage: "table")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let r = model.result, !r.rows.isEmpty {
                    Button("Export CSV…") { exportCSV(r) }
                        .help("Save the current result set as a CSV file.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().overlay(AccessTheme.gridLine)

            if let result = model.result {
                if result.isDataQuery {
                    ResultGrid(result: result)
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("\(result.rowCount) row\(result.rowCount == 1 ? "" : "s") affected")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AccessTheme.datasheetBackground)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Results will appear here")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AccessTheme.datasheetBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.datasheetBackground)
    }

    private func exportCSV(_ result: QueryResult) {
        var lines: [String] = []
        lines.append(result.columns.map(escapeCSV).joined(separator: ","))
        for row in result.rows {
            let values = result.columns.map { col in
                (row.values[col] ?? .null).displayText
            }
            lines.append(values.map(escapeCSV).joined(separator: ","))
        }
        let csv = lines.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.title = "Export CSV"
        panel.nameFieldStringValue = "query_results.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

struct HistorySheet: View {
    let history: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Query History")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(history.count) saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(history.enumerated()), id: \.offset) { index, entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            Text(SQLAttributed(entry, dark: false).attributed)
                                .font(.custom("Menlo", size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 4).fill(index % 2 == 0 ? Color.white : AccessTheme.alternateRow))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AccessTheme.gridLine))
                    }
                }
                .padding(4)
            }
            .background(AccessTheme.datasheetBackground)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 440)
        .background(AccessTheme.windowBackground)
    }
}

struct ResultGrid: View {
    let result: QueryResult

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(result.columns, id: \.self) { col in
                        Text(col)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AccessTheme.headerText)
                            .frame(width: 140, height: 28, alignment: .leading)
                            .padding(.leading, 8)
                            .background(
                                LinearGradient(colors: [AccessTheme.headerBackgroundTop, AccessTheme.headerBackgroundBottom], startPoint: .top, endPoint: .bottom)
                            )
                            .overlay(alignment: .trailing) { Divider().overlay(AccessTheme.gridLine) }
                    }
                }

                // Rows
                ForEach(Array(result.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 0) {
                        ForEach(result.columns, id: \.self) { col in
                            let value = row.values[col] ?? .null
                            Text(value.displayText)
                                .font(.custom("Menlo", size: 11.5))
                                .lineLimit(1)
                                .frame(width: 140, height: 26, alignment: .leading)
                                .padding(.leading, 8)
                                .foregroundStyle(value == .null ? AccessTheme.nullText : AccessTheme.cellText)
                                .background(index % 2 == 1 ? AccessTheme.alternateRow : Color.white)
                                .overlay(alignment: .trailing) { Divider().overlay(AccessTheme.gridLine) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(AccessTheme.datasheetBackground)
    }
}

/// Access-style prominent button: maroon-red fill.
struct AccessProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        configuration.isPressed
                            ? AccessTheme.appAccentDark
                            : AccessTheme.appAccent
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(configuration.isPressed ? AccessTheme.appAccentDark : AccessTheme.appAccentLight, lineWidth: 1)
            )
    }
}