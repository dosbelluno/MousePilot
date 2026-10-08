import AppKit
import SwiftUI

/// Renders a mock UI offscreen. No window, input tap, settings read, or timer is
/// created; this is visual QA of the artifact, not control of the user's desktop.
@MainActor
enum AppPreview {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, scheme, appearanceName) in [
            ("light", ColorScheme.light, NSAppearance.Name.aqua),
            ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua)
        ] {
            for page in NavigationPage.allCases {
                let store = AppStore(preview: true)
                store.page = page
                let view = NSHostingView(rootView: MainView(store: store).environment(\.colorScheme, scheme))
                view.frame = NSRect(x: 0, y: 0, width: 860, height: 740)
                view.appearance = NSAppearance(named: appearanceName)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let prefix = page == .mappings ? "main" : "settings"
                try png.write(to: directory.appendingPathComponent("\(prefix)-\(name).png"))
            }
        }
    }
}
