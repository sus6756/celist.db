import SwiftUI
import CelistDBCore

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SidebarSelection?

    var body: some View {
        VStack(spacing: 0) {
            RibbonView(selection: $selection)

            if appState.isOpen {
                mainContent
            } else {
                WelcomeView(onOpen: openDatabase, onCreate: createDatabase, onSample: createSample)
            }

            StatusBarView(selection: selection)
        }
        .preferredColorScheme(.light)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.windowBackground)
        .onChange(of: selection) {
            updateCurrentTable()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { appState.openErrorMessage != nil },
                set: { if !$0 { appState.openErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.openErrorMessage ?? "")
        }
    }

    private var mainContent: some View {
        HSplitView {
            NavigationPaneView(selection: $selection)
            DetailView(selection: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func updateCurrentTable() {
        switch selection {
        case .table(let name):
            appState.currentTableName = name
        case .query, .newTable, .none:
            appState.currentTableName = nil
        }
    }

    private func openDatabase() { AppActions.openDatabase(appState: appState) }
    private func createDatabase() { AppActions.newDatabase(appState: appState) }
    private func createSample() { AppActions.createSample(appState: appState) }
}

enum SidebarSelection: Hashable {
    case table(String)
    case newTable
    case query
}

struct DetailView: View {
    let selection: SidebarSelection?
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch selection {
        case .none:
            EmptySelectionView()
        case .table(let name):
            TableDetailView(model: appState.viewModel(for: name))
        case .newTable:
            TableDesignerView(model: appState.designerVM())
                .background(AccessTheme.windowBackground)
        case .query:
            QueryView(model: appState.queryVM())
        }
    }
}

struct EmptySelectionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Pick a table to browse its data")
                .font(.title3)
            Text("…or press ⏎ New Table to design your first one, or SQL Query to run raw SQL.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AccessTheme.windowBackground)
    }
}