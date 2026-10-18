import Foundation
import Combine
import CelistDBCore

/// Backs the spreadsheet data grid for one table.
@MainActor
final class TableViewModel: ObservableObject {
    let service: DatabaseService
    let tableName: String

    @Published var schema: TableSchema?
    @Published var rows: [DataRow] = []
    @Published var totalCount: Int64 = 0
    @Published var isLoading = false
    @Published var statusMessage: String?
    /// The original DDL for this object, shown in the SQL tab (best-effort).
    @Published var createSQL: String?

    @Published var searchText = "" {
        didSet { debounceReload() }
    }
    @Published var sortColumn: String?
    @Published var sortAscending = true
    /// The row currently selected in the datasheet (drives ribbon commands).
    @Published var selectedRowID: Int64? {
        didSet { if oldValue != selectedRowID { onSelectedRowChanged?(selectedRowID) } }
    }
    /// Called whenever `selectedRowID` changes so AppState can relay
    /// the value to views that only observe AppState (e.g. RibbonView).
    var onSelectedRowChanged: ((Int64?) -> Void)?
    /// The row pending deletion confirmation (drives the confirmation alert).
    @Published var confirmDeleteRow: DataRow?
    @Published private(set) var errorMessage: String?
    @Published private(set) var pageLimit: Int = 500
    @Published private(set) var loadedOffset: Int = 0
    @Published private(set) var totalPages: Int64 = 1
    @Published private(set) var currentPage: Int64 = 0
    private var isLoadedMore = false

    private var loadTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init(service: DatabaseService, tableName: String) {
        self.service = service
        self.tableName = tableName
        reloadSchema()
        reload()
    }

    var columns: [SchemaColumn] {
        schema?.columns ?? []
    }

    /// Views are browsable but not editable.
    var isView: Bool { schema?.isView == true }

    /// The column the ribbon's Sort commands should act on; set when a cell
    /// is clicked so "Ascending"/"Descending" reflect the user's selection.
    @Published var selectedColumn: String?

    // MARK: - Load

    func reloadSchema() {
        do {
            schema = try service.schema(for: tableName)
            createSQL = try service.createSQL(for: tableName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        loadedOffset = 0
        currentPage = 0
        isLoadedMore = false
        load(reset: true)
    }

    func goToPage(_ page: Int64) {
        guard page >= 0, page < totalPages, page != currentPage else { return }
        currentPage = page
        loadedOffset = Int(page) * pageLimit
        isLoadedMore = false
        load(reset: true)
    }

    func movePage(by delta: Int64) {
        goToPage(currentPage + delta)
    }

    func loadMoreIfNeeded() {
        guard !isLoadedMore, rows.count > 0, rows.count < totalCount else { return }
        isLoadedMore = true
        loadedOffset += pageLimit
        load(reset: false)
    }

    private func load(reset: Bool) {
        loadTask?.cancel()
        let state = GridState(
            searchText: searchText,
            sortColumn: sortColumn,
            ascending: sortAscending,
            limit: pageLimit,
            offset: loadedOffset
        )
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try self.service.fetchRows(in: self.tableName, state: state)
                try Task.checkCancellation()
                self.totalCount = result.totalCount
                self.totalPages = max(1, (result.totalCount + Int64(self.pageLimit) - 1) / Int64(self.pageLimit))
                self.currentPage = max(0, min(self.currentPage, self.totalPages - 1))
                self.rows = reset ? result.rows : self.rows + result.rows
                // Keep a "current record" like Access: once rows are present,
                // ensure one is selected so Duplicate/Delete stay enabled.
                if self.rows.isEmpty {
                    self.selectedRowID = nil
                } else if self.selectedRowID == nil
                    || !self.rows.contains(where: { $0.rowID == self.selectedRowID }) {
                    self.selectedRowID = self.rows.first?.rowID
                }
                self.isLoading = false
            } catch is CancellationError {
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func debounceReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.reload()
        }
    }

    func toggleSort(column name: String) {
        if sortColumn == name {
            sortAscending.toggle()
        } else {
            sortColumn = name
            sortAscending = true
        }
        reload()
    }

    func sortIndicator(for name: String) -> String {
        guard sortColumn == name else { return "" }
        return sortAscending ? "▲" : "▼"
    }

    // MARK: - Mutations

    func addRow() {
        guard !isView else {
            errorMessage = "Views are read-only. Add rows to the underlying table."
            return
        }
        do {
            // Insert placeholders only where a NULL would violate a NOT NULL
            // constraint with no default; other columns are omitted so their
            // DEFAULTs (and the auto-increment key) apply as normal.
            var values: [String: CellValue] = [:]
            for col in columns where col.primaryKeyIndex == 0 {
                if col.isNotNull && col.defaultValueSQL == nil {
                    values[col.name] = Self.placeholder(for: col.affinity)
                }
            }
            _ = try service.insertRow(in: tableName, values: values)
            statusMessage = "Added a row"
            reload()
            reloadSchema()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicateRow(_ row: DataRow) {
        guard !isView else {
            errorMessage = "Views are read-only."
            return
        }
        do {
            // Omit primary-key columns so the database assigns a fresh key.
            let pk = Set(schema?.primaryKeyColumns ?? [])
            var values = row.values
            for key in pk { values.removeValue(forKey: key) }
            _ = try service.insertRow(in: tableName, values: values)
            statusMessage = "Duplicated row"
            reload()
            reloadSchema()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRow(_ row: DataRow) {
        guard !isView else {
            errorMessage = "Views are read-only."
            return
        }
        do {
            try service.deleteRow(rowID: row.rowID, in: tableName)
            statusMessage = "Deleted row"
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commitEdit(_ value: CellValue, column: String, rowID: Int64) {
        guard !isView else {
            errorMessage = "Views are read-only."
            return
        }
        do {
            try service.updateCell(value, column: column, rowID: rowID, in: tableName)
            // Optimistically update the in-memory row.
            if let idx = rows.firstIndex(where: { $0.rowID == rowID }) {
                var dict = rows[idx].values
                dict[column] = value
                rows[idx] = DataRow(rowID: rowID, values: dict)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A benign value to seed a required column that has no default.
    private static func placeholder(for affinity: ColumnAffinity) -> CellValue {
        switch affinity {
        case .integer: return .integer(0)
        case .real: return .real(0)
        case .boolean: return .bool(false)
        case .blob, .text: return .text("")
        }
    }

    func affinity(for column: String) -> ColumnAffinity {
        columns.first(where: { $0.name == column })?.affinity ?? .text
    }

    // MARK: - Ribbon-driven actions

    func ribbonSortColumn(ascending: Bool) {
        guard let col = selectedColumn ?? sortColumn ?? columns.first?.name else { return }
        sortColumn = col
        sortAscending = ascending
        reload()
    }

    func clearFilterAndSort() {
        searchText = ""
        sortColumn = nil
        sortAscending = true
        reload()
    }

    func requestDelete() {
        guard let id = selectedRowID else { return }
        if let r = rows.first(where: { $0.rowID == id }) {
            confirmDeleteRow = r
        }
    }

    func confirmDelete() {
        if let r = confirmDeleteRow {
            deleteRow(r)
        }
        confirmDeleteRow = nil
    }

    func cancelDelete() {
        confirmDeleteRow = nil
    }
}