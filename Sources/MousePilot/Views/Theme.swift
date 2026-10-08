import SwiftUI

// Native surfaces follow the Mac's light/dark appearance.
enum PilotTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let raised = Color.primary.opacity(0.045)
    static let accent = Color(red: 0.35, green: 0.52, blue: 0.95)
    static let muted = Color.secondary
    static let line = Color.primary.opacity(0.07)
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(padding)
            .background(PilotTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PilotTheme.line))
    }
}

struct SmallLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
}

struct ShortcutBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(PilotTheme.raised, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(PilotTheme.accent.opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 9))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.6 : 0.85))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(PilotTheme.raised, in: RoundedRectangle(cornerRadius: 8))
    }
}
