import Foundation
import Combine
import CelistDBCore

/// Backs the raw SQL editor + results grid + history.
@MainActor
final class QueryViewModel: ObservableObject {
    let service: DatabaseService

    @Published var sql = ""
    @Published var result: QueryResult?
    @Published var errorMessage: String?
    @Published var isRunning = false
    @Published var objects: [SchemaObject] = []
    @Published private(set) var history: [String] = []

    init(service: DatabaseService) {
        self.service = service
        self.history = Self.loadHistory(for: service)
        reloadObjects()
    }

    /// History is persisted per database so it survives relaunches.
    private static func historyKey(for service: DatabaseService) -> String {
        "celistdb.queryHistory." + service.databaseURL.standardizedFileURL.path
    }

    private static func loadHistory(for service: DatabaseService) -> [String] {
        (UserDefaults.standard.array(forKey: historyKey(for: service)) as? [String]) ?? []
    }

    private func persistHistory() {
        UserDefaults.standard.set(history, forKey: Self.historyKey(for: service))
    }

    func reloadObjects() {
        do {
            objects = try service.listObjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func run() {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRunning = true
        errorMessage = nil
        do {
            let r = try service.runSQL(trimmed)
            result = r
            addToHistory(trimmed)
            reloadObjects()
        } catch {
            errorMessage = error.localizedDescription
            result = nil
        }
        isRunning = false
    }

    func runSample(_ sample: String) {
        sql = sample
        run()
    }

    private func addToHistory(_ entry: String) {
        history.removeAll { $0 == entry }
        history.insert(entry, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        persistHistory()
    }

    func useHistory(_ entry: String) {
        sql = entry
    }
}