import AppKit
import MousePilotCore
import SwiftUI

struct MappingEditor: View {
    @ObservedObject var store: AppStore
    let session: EditingSession
    @Environment(\.dismiss) private var dismiss
    @State private var mapping: MouseMapping
    @State private var recordingShortcut = false

    init(store: AppStore, session: EditingSession) {
        self.store = store
        self.session = session
        let freeButton = (2...31).first { button in
            !store.configuration.mappings.contains { $0.trigger == .init(button: button) }
        } ?? 2
        _mapping = State(initialValue: session.mapping ?? .init(trigger: .init(button: freeButton), action: .missionControl))
    }

    private var exists: Bool { store.configuration.mappings.contains { $0.id == mapping.id } }
    private var duplicate: Bool {
        store.configuration.mappings.contains { $0.id != mapping.id && $0.trigger == mapping.trigger }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    SmallLabel(text: "MousePilot")
                    Text(exists ? "동작 편집" : "동작 추가").font(.system(size: 23, weight: .semibold))
                }
                Spacer()
                Image(systemName: "computermouse").font(.system(size: 27)).foregroundStyle(PilotTheme.accent)
            }
            Panel {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Label("입력", systemImage: "1.circle.fill").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if store.captureOwner == session.id {
                            Button("감지 취소") { store.cancelCapture(owner: session.id) }.buttonStyle(QuietButtonStyle())
                        } else {
                            Button { store.startCapture(owner: session.id) } label: {
                                Label("버튼 찾기", systemImage: "dot.radiowaves.left.and.right")
                            }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    if store.captureOwner == session.id {
                        Text("지정할 버튼을 눌러 주세요.")
                            .font(.system(size: 12)).foregroundStyle(PilotTheme.accent)
                    }
                    Picker("버튼", selection: $mapping.trigger.button) {
                        ForEach(2...31, id: \.self) { button in
                            Text(MouseTrigger(button: button).buttonName).tag(button)
                        }
                    }.pickerStyle(.menu)
                    Picker("제스처", selection: $mapping.trigger.gesture) {
                        ForEach(MouseGesture.allCases) { gesture in Text(gesture.title).tag(gesture) }
                    }.pickerStyle(.menu)
                    if mapping.trigger.gesture != .click {
                        Text("버튼을 누른 채 움직이고 놓으면 실행됩니다.")
                            .font(.system(size: 11)).foregroundStyle(PilotTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Text("보조 키").font(.system(size: 12)).foregroundStyle(PilotTheme.muted)
                        HStack(spacing: 7) {
                            modifierButton(.control, label: "⌃ Control")
                            modifierButton(.option, label: "⌥ Option")
                            modifierButton(.shift, label: "⇧ Shift")
                            modifierButton(.command, label: "⌘ Command")
                            modifierButton(.function, label: "fn")
                        }
                    }
                    Text(mapping.trigger.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(PilotTheme.accent)
                    if duplicate {
                        Label("이미 지정된 입력입니다.", systemImage: "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                    }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 17) {
                    Label("동작", systemImage: "2.circle.fill").font(.system(size: 13, weight: .semibold))
                    Picker("동작", selection: $mapping.action) {
                        ForEach(ActionKind.allCases) { action in Text(action.title).tag(action) }
                    }.pickerStyle(.menu)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(mapping.action == .customShortcut ? "사용자 지정 단축키" : "단축키")
                                .font(.system(size: 12)).foregroundStyle(PilotTheme.muted)
                            Spacer()
                            if mapping.shortcutOverride != nil && mapping.action != .customShortcut {
                                Button("기본값 복원") { mapping.shortcutOverride = nil }
                                    .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(PilotTheme.accent)
                            }
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(recordingShortcut ? PilotTheme.accent.opacity(0.07) : PilotTheme.background)
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(recordingShortcut ? PilotTheme.accent : PilotTheme.line))
                            HStack {
                                Image(systemName: "keyboard").foregroundStyle(PilotTheme.muted)
                                Text(recordingShortcut ? "단축키를 눌러 주세요" : (mapping.effectiveShortcut?.displayName ?? "클릭하여 단축키 입력"))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                Spacer()
                                Text(recordingShortcut ? "기록 중" : "변경")
                                    .font(.system(size: 11)).foregroundStyle(PilotTheme.accent)
                            }.padding(.horizontal, 13).allowsHitTesting(false)
                            ShortcutCaptureView(isRecording: recordingShortcut,
                                onStart: { recordingShortcut = true },
                                onCancel: { recordingShortcut = false },
                                onRecord: { shortcut in mapping.shortcutOverride = shortcut; recordingShortcut = false })
                        }.frame(height: 48)
                        Text("클릭한 뒤 단축키를 눌러 주세요. Esc로 취소합니다.")
                            .font(.system(size: 11)).foregroundStyle(PilotTheme.muted).lineSpacing(3)
                    }
                }
            }
            HStack {
                if exists {
                    Button("삭제", role: .destructive) {
                        store.deleteMapping(id: mapping.id)
                        dismiss()
                    }.buttonStyle(.borderless).foregroundStyle(.orange).font(.system(size: 12))
                }
                Spacer()
                Button("취소") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button("저장") {
                    if store.saveMapping(mapping) { dismiss() }
                }.buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(duplicate || !mapping.isValid || recordingShortcut || store.captureOwner == session.id)
                    .opacity(duplicate || !mapping.isValid ? 0.4 : 1)
            }
        }
        .padding(28).frame(width: 610)
        .background(PilotTheme.background).tint(PilotTheme.accent)

        .onChange(of: store.capturedInput) { _, captured in
            if let captured, captured.owner == session.id {
                mapping.trigger = .init(button: captured.trigger.button, modifiers: captured.trigger.modifiers,
                                        gesture: mapping.trigger.gesture)
            }
        }
        .onChange(of: mapping.action) { _, _ in
            mapping.shortcutOverride = nil
            recordingShortcut = false
        }
        .onDisappear { store.endCaptureSession(owner: session.id) }
    }

    private func modifierButton(_ modifier: Modifiers, label: String) -> some View {
        let selected = mapping.trigger.modifiers.contains(modifier)
        return Button {
            if selected { mapping.trigger.modifiers.remove(modifier) }
            else { mapping.trigger.modifiers.insert(modifier) }
        } label: {
            Text(label).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 8)
                .foregroundStyle(selected ? PilotTheme.accent : PilotTheme.muted)
                .background(selected ? PilotTheme.accent.opacity(0.10) : PilotTheme.raised, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? PilotTheme.accent.opacity(0.5) : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onStart: () -> Void
    let onCancel: () -> Void
    let onRecord: (MousePilotCore.KeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView { ShortcutCaptureNSView() }
    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onStart = onStart
        view.onCancel = onCancel
        view.onRecord = onRecord
        if isRecording && !view.isRecording {
            DispatchQueue.main.async { [weak view] in
                if let view { view.window?.makeFirstResponder(view) }
            }
        }
        view.isRecording = isRecording
    }
}

private final class ShortcutCaptureNSView: NSView {
    var isRecording = false
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRecord: ((MousePilotCore.KeyboardShortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("단축키 입력")
        setAccessibilityHelp("선택한 뒤 원하는 키 조합을 누르세요. Esc로 취소할 수 있습니다.")
    }

    required init?(coder: NSCoder) { nil }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        onStart?()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onStart?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        var modifiers = Modifiers(cgFlags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
        // Arrow/function key events may include the NSEvent function flag themselves.
        // Only record fn when the physical modifier is actually held.
        if !CGEventSource.keyState(.hidSystemState, key: 63) { modifiers.remove(.function) }
        if event.keyCode == 53 && modifiers.isEmpty { onCancel?(); return }
        let label = Self.keyLabels[event.keyCode]
            // The command layout supplies familiar shortcut labels even when an IME
            // is active (for example A instead of the Korean character ㅁ).
            ?? event.characters(byApplyingModifiers: .command)?.uppercased()
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "Key \(event.keyCode)"
        let shortcut = MousePilotCore.KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers, keyLabel: label)
        if shortcut.isValid { onRecord?(shortcut) }
    }

    private static let keyLabels: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc", 76: "Enter", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15"
    ]
}
