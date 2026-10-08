import AppKit
import SwiftUI

@main
struct MousePilotApp: App {
    @NSApplicationDelegateAdaptor(PilotAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.indices.contains(index + 1) {
            do {
                try AppPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            } catch { print(error.localizedDescription); exit(1) }
            exit(0)
        }
        if CommandLine.arguments.contains("--diagnose") {
            let report = AppDiagnostics.report()
            print(report)
            do { try AppDiagnostics.save(report) }
            catch { print("Could not save diagnostics: \(error.localizedDescription)"); exit(1) }
            exit(0)
        }
    }

    var body: some Scene {
        Window("MousePilot", id: "main") {
            MainView(store: store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.shutdown()
                }
        }
        .defaultSize(width: 860, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("설정…") { store.page = .settings; NSApp.activate(ignoringOtherApps: true) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent(store: store)
        } label: {
            Image(systemName: store.isActive ? "computermouse.fill" : "computermouse")
        }
    }
}

@MainActor
private final class PilotAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct MenuBarContent: View {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("MousePilot · \(store.statusTitle)")
        Toggle("사용", isOn: Binding(get: { store.configuration.isEnabled }, set: { store.setEnabled($0) }))
        Divider()
        Button("제스처…") {
            store.page = .mappings
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("설정…") {
            store.page = .settings
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("MousePilot 종료") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
