import SwiftUI
import AppKit

/// Access-style status bar: a light grey bar with the current status on the
/// left and contextual view-type buttons on the right.
struct StatusBarView: View {
    @EnvironmentObject var appState: AppState
    let selection: SidebarSelection?

    var body: some View {
        HStack(spacing: 10) {
            Text("Ready")
                .font(.system(size: 11))
                .foregroundStyle(AccessTheme.statusBarText)

            if let label = contextLabel {
                Rectangle().fill(AccessTheme.statusBarBorder).frame(width: 1, height: 14)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(AccessTheme.statusBarText)
            }

            Spacer()

            if let viewMode = currentViewMode {
                HStack(spacing: 2) {
                    ForEach(viewMode.icons, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundStyle(AccessTheme.statusBarText)
                            .frame(width: 22, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(AccessTheme.statusBarBorder))
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(AccessTheme.statusBar)
        .overlay(alignment: .top) {
            Rectangle().fill(AccessTheme.statusBarBorder).frame(height: 1)
        }
    }

    private enum ViewMode {
        case table, query, designer

        var icons: [String] {
            switch self {
            case .table: return ["tablecells", "wrench.and.screwdriver", "terminal"]
            case .query: return ["terminal", "tablecells"]
            case .designer: return ["wrench.and.screwdriver", "tablecells"]
            }
        }
    }

    private var currentViewMode: ViewMode? {
        switch selection {
        case .table: return .table
        case .query: return .query
        case .newTable: return .designer
        case .none: return nil
        }
    }

    private var contextLabel: String? {
        switch selection {
        case .table(let name): return "Table · \(name)"
        case .query: return "Query · SQL View"
        case .newTable: return "Table Design"
        case .none: return nil
        }
    }
}