import Foundation

/// Result of running one or more SQL statements.
public struct QueryResult: Sendable {
    public let columns: [String]
    public let rows: [DataRow]
    public let statementIndex: Int    // which statement produced this result (for multi-statement runs)
    public let rowCount: Int64        // INSERT/UPDATE/DELETE affected rows, when reported
    public let isDataQuery: Bool      // true when rows/columns are populated

    public static let empty = QueryResult(columns: [], rows: [], statementIndex: 0, rowCount: 0, isDataQuery: false)

    public init(columns: [String], rows: [DataRow], statementIndex: Int, rowCount: Int64, isDataQuery: Bool) {
        self.columns = columns
        self.rows = rows
        self.statementIndex = statementIndex
        self.rowCount = rowCount
        self.isDataQuery = isDataQuery
    }
}

public struct QueryRunError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// An immutable snapshot of one tab's current sort/filter state.
public struct GridState: Equatable {
    public var searchText: String = ""
    public var sortColumn: String?
    public var ascending: Bool = true
    public var limit: Int = 500
    public var offset: Int = 0

    public init(
        searchText: String = "",
        sortColumn: String? = nil,
        ascending: Bool = true,
        limit: Int = 500,
        offset: Int = 0
    ) {
        self.searchText = searchText
        self.sortColumn = sortColumn
        self.ascending = ascending
        self.limit = limit
        self.offset = offset
    }
}