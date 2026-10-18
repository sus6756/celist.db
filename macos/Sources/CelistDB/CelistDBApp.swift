import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CelistDBCore

@main
struct CelistDBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Database…") { openNewDatabase() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { openDatabase() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Create Sample Database…") { createSample() }
            }
        }
    }

    private func openNewDatabase() {
        AppActions.newDatabase(appState: appState)
    }

    private func openDatabase() {
        AppActions.openDatabase(appState: appState)
    }

    private func createSample() {
        AppActions.createSample(appState: appState)
    }
}

/// Ensures the app is foreground-active and its window becomes key so that
/// text fields (designer, SQL editor) reliably accept keyboard input —
/// important when launched via `swift run` from a terminal (which otherwise
/// lacks the normal bundle-based activation that makes the window key).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        activateFront()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc func applicationDidBecomeActive(_ notification: Notification) {
        activateFront()
    }

    private func activateFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            Self.pointFocus()
        }
    }

    /// Recursively bring the main window forward until it is key.
    private static func pointFocus(retries: Int = 4) {
        let windows = NSApp.windows.filter { $0.canBecomeKey }
        guard let window = windows.first else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pointFocus(retries: retries - 1)
                }
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !window.isKeyWindow && retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pointFocus(retries: retries - 1)
            }
        }
    }
}

/// Reusable file-dialog actions shared by the menu and welcome screen.
@MainActor
enum AppActions {
    private static var dbType: UTType { UTType(filenameExtension: "db") ?? .data }
    private static var sqliteType: UTType { UTType(filenameExtension: "sqlite") ?? .data }
    private static var sqlite3Type: UTType { UTType(filenameExtension: "sqlite3") ?? .data }
    private static var openTypes: [UTType] { [dbType, sqliteType, sqlite3Type, .data] }

    static func newDatabase(appState: AppState) {
        let panel = NSSavePanel()
        panel.title = "Create Database"
        panel.nameFieldLabel = "Name:"
        panel.nameFieldStringValue = "MyDatabase.db"
        panel.allowedContentTypes = [dbType]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            var fileURL = url
            if fileURL.pathExtension.lowercased() != "db" {
                fileURL.appendPathExtension("db")
            }
            do {
                try appState.newLocalDatabase(at: fileURL)
            } catch {
                appState.openErrorMessage = error.localizedDescription
            }
        }
    }

    static func openDatabase(appState: AppState) {
        let panel = NSOpenPanel()
        panel.title = "Open Database"
        panel.allowedContentTypes = openTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try appState.open(url: url)
            } catch {
                appState.openErrorMessage = error.localizedDescription
            }
        }
    }

    static func createSample(appState: AppState) {
        let panel = NSSavePanel()
        panel.title = "Create Sample Database"
        panel.nameFieldLabel = "Name:"
        panel.nameFieldStringValue = "Sample Shop.db"
        panel.allowedContentTypes = [dbType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var fileURL = url
        if fileURL.pathExtension.lowercased() != "db" {
            fileURL.appendPathExtension("db")
        }
        do {
            try SampleDatabase.create(at: fileURL)
            try appState.open(url: fileURL)
        } catch {
            appState.openErrorMessage = error.localizedDescription
        }
    }
}