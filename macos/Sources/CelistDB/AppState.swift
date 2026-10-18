import Foundation
import AppKit
import CelistDBCore

/// Central app state: owns the current database service and the working
/// view-model per table/query. Observable so SwiftUI re-renders on navigation.
@MainActor
final class AppState: ObservableObject {
    @Published var service: DatabaseService?
    @Published var openErrorMessage: String?
    /// Increments each time a database is opened/closed so views can re-derive.
    @Published var dbGeneration = 0
    /// The ribbon tab currently selected.
    @Published var activeRibbonTab: RibbonTab = .home
    /// The table whose datasheet is being viewed (drives contextual ribbon commands).
    @Published var currentTableName: String?
    /// Relays the selected row from the current TableViewModel so that
    /// RibbonView (which only observes AppState) re-renders when the
    /// selection changes.
    @Published var currentSelectedRowID: Int64?

    private(set) var tableViewModels: [String: TableViewModel] = [:]
    private(set) var queryViewModel: QueryViewModel?
    private(set) var designerViewModel: TableDesignerViewModel?

    var isOpen: Bool { service != nil }

    func open(url: URL) throws {
        let svc = try SQLiteService(url: url)
        close()
        self.service = svc
        self.openErrorMessage = nil
        dbGeneration += 1
        rebuildAll()
    }

    func newLocalDatabase(at url: URL) throws {
        let svc = try SQLiteService(url: url)
        close()
        self.service = svc
        self.openErrorMessage = nil
        dbGeneration += 1
        rebuildAll()
    }

    func close() {
        queryViewModel = nil
        designerViewModel = nil
        tableViewModels.removeAll()
        if let svc = service {
            svc.close()
        }
        service = nil
        currentTableName = nil
        currentSelectedRowID = nil
        openErrorMessage = nil
        dbGeneration += 1
    }

    func refreshAll() {
        rebuildAll()
    }

    func viewModel(for table: String) -> TableViewModel {
        if let vm = tableViewModels[table] { return vm }
        let vm = TableViewModel(service: service!, tableName: table)
        vm.onSelectedRowChanged = { [weak self] rowID in
            self?.currentSelectedRowID = rowID
        }
        tableViewModels[table] = vm
        return vm
    }

    /// The table VM backing the currently-viewed datasheet, if any.
    func currentTable() -> TableViewModel? {
        guard let name = currentTableName else { return nil }
        return viewModel(for: name)
    }

    func queryVM() -> QueryViewModel {
        if let q = queryViewModel { return q }
        let q = QueryViewModel(service: service!)
        queryViewModel = q
        return q
    }

    func designerVM() -> TableDesignerViewModel {
        if let d = designerViewModel { return d }
        let d = TableDesignerViewModel(service: service!)
        d.onTableCreated = { [weak self] in
            self?.reloadAfterSchemaChange()
        }
        designerViewModel = d
        return d
    }

    func reloadAfterSchemaChange() {
        refreshAll()
        queryViewModel?.reloadObjects()
        // Bump generation so the navigation pane path observes the change
        // and re-lists tables/views (it reloads on dbGeneration change).
        dbGeneration += 1
    }

    private func rebuildAll() {
        tableViewModels.removeAll()
        designerViewModel = nil
        queryViewModel = nil
    }
}