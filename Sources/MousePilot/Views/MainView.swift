import AppKit
import MousePilotCore
import SwiftUI

struct EditingSession: Identifiable {
    let id = UUID()
    let mapping: MouseMapping?
}

struct MainView: View {
    @ObservedObject var store: AppStore
    @State private var editor: EditingSession?
    @State private var threshold = 60.0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(PilotTheme.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let notice = store.notice { noticeBanner(notice) }
                    switch store.page {
                    case .mappings: gestures
                    case .settings: SettingsView(store: store)
                    }
                }
                .padding(26).frame(maxWidth: 960)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack {
                Text("MousePilot 0.4.0")
                Spacer()
                Text("메뉴 막대에서 계속 실행됩니다")
            }
            .font(.system(size: 10)).foregroundStyle(.tertiary)
            .padding(.horizontal, 26).padding(.bottom, 14)
        }
        .frame(minWidth: 800, minHeight: 650)
        .background(PilotTheme.background).tint(PilotTheme.accent)
        .sheet(item: $editor) { MappingEditor(store: store, session: $0) }
        .alert("MousePilot", isPresented: Binding(get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })) {
            Button("확인", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 20)).foregroundStyle(PilotTheme.accent)
                Text("MousePilot").font(.system(size: 17, weight: .semibold))
            }
            Spacer()
            Picker("화면", selection: $store.page) {
                ForEach(NavigationPage.allCases) { page in Text(page.title).tag(page) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(store.isActive ? PilotTheme.accent : Color.secondary.opacity(0.45))
                    .frame(width: 5, height: 5)
                Text(store.statusTitle).font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("사용", isOn: Binding(get: { store.configuration.isEnabled }, set: { store.setEnabled($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
        }.padding(.horizontal, 26).padding(.vertical, 19)
    }

    private var gestures: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !store.permissions.isReady {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(PilotTheme.accent)
                    Text("손쉬운 사용을 허용해 주세요.").font(.system(size: 12))
                    Spacer()
                    Button("설정 열기") { store.page = .settings }.buttonStyle(QuietButtonStyle())
                }.padding(14).background(PilotTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 24) {
                MouseArtwork().frame(width: 168, height: 122)
                VStack(alignment: .leading, spacing: 9) {
                    Text("휠 제스처").font(.system(size: 25, weight: .semibold))
                    Text("휠을 누른 채 움직이고 놓으세요.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 28, weight: .ultraLight)).foregroundStyle(PilotTheme.accent.opacity(0.35))
                    .padding(.trailing, 26)
            }
            .padding(.horizontal, 15)

            HStack {
                Text("버튼 동작").font(.system(size: 14, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(MousePreset.allCases) { preset in
                        Button(preset.title) { store.applyPreset(preset) }
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
                    .help("기본 동작 선택")
                Button { editor = .init(mapping: nil) } label: { Label("추가", systemImage: "plus") }
                    .buttonStyle(QuietButtonStyle())
            }
            VStack(spacing: 0) {
                if store.configuration.mappings.isEmpty {
                    Text("버튼 동작을 추가해 주세요.").font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(30).frame(maxWidth: .infinity)
                }
                ForEach(Array(store.configuration.mappings.enumerated()), id: \.element.id) { index, mapping in
                    mappingRow(mapping)
                    if index < store.configuration.mappings.count - 1 {
                        Rectangle().fill(PilotTheme.line).frame(height: 1).padding(.leading, 62)
                    }
                }
            }.background(PilotTheme.panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(PilotTheme.line))

            Panel(padding: 16) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("이동 거리").font(.system(size: 12, weight: .medium))
                        Text("낮을수록 짧은 움직임에 반응합니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Slider(value: $threshold, in: 16...240, step: 4, onEditingChanged: { editing in
                        if !editing { store.setGestureThreshold(threshold) }
                    }).frame(width: 170).accessibilityLabel("제스처 이동 거리")
                    Text("\(Int(threshold))").font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 28)
                }
            }
            .onAppear { threshold = store.configuration.gestureThreshold }
            .onChange(of: store.configuration.gestureThreshold) { _, value in threshold = value }
        }
    }

    private func mappingRow(_ mapping: MouseMapping) -> some View {
        HStack(spacing: 13) {
            Image(systemName: mapping.trigger.gesture.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(mapping.isEnabled ? PilotTheme.accent : Color.secondary)
                .frame(width: 31, height: 31)
                .background(PilotTheme.accent.opacity(mapping.isEnabled ? 0.085 : 0.025), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(inputTitle(mapping.trigger)).font(.system(size: 12, weight: .medium))
                Text(mapping.trigger.modifiers.symbols + mapping.trigger.buttonName)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(width: 122, alignment: .leading)
            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(mapping.action.title).font(.system(size: 12)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShortcutBadge(text: mapping.effectiveShortcut?.displayName ?? "미지정")
            Button { editor = .init(mapping: mapping) } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 12))
            }.buttonStyle(.borderless).foregroundStyle(.secondary)
                .accessibilityLabel("\(mapping.trigger.displayName) 편집").help("동작 편집")
            Toggle("\(mapping.trigger.displayName) 사용", isOn: Binding(get: { mapping.isEnabled },
                set: { store.setMappingEnabled(id: mapping.id, enabled: $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.mini)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .opacity(mapping.isEnabled ? 1 : 0.45)
    }

    private func inputTitle(_ trigger: MouseTrigger) -> String {
        switch trigger.gesture {
        case .click: "클릭"
        case .swipeLeft: "왼쪽"
        case .swipeRight: "오른쪽"
        case .swipeUp: "위"
        case .swipeDown: "아래"
        }
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(spacing: 10) {
            Text(notice).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if store.previousConfiguration != nil {
                Button("되돌리기") { store.undo() }.buttonStyle(.borderless).font(.system(size: 11))
            }
            Button { store.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("알림 닫기")
        }.padding(12).background(PilotTheme.raised, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MouseArtwork: View {
    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.06)).frame(width: 95, height: 17).blur(radius: 8).offset(y: 55)
            RoundedRectangle(cornerRadius: 33)
                .fill(LinearGradient(colors: [Color(white: 0.83), Color(white: 0.64)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 66, height: 106)
                .overlay(RoundedRectangle(cornerRadius: 33).strokeBorder(.white.opacity(0.4)))
            Rectangle().fill(.black.opacity(0.16)).frame(width: 1, height: 38).offset(y: -42)
            Capsule().fill(PilotTheme.accent).frame(width: 8, height: 23).offset(y: -38)
            Capsule().fill(.black.opacity(0.18)).frame(width: 3, height: 13).offset(x: -38, y: -16)
            Capsule().fill(.black.opacity(0.18)).frame(width: 3, height: 13).offset(x: -37, y: -34)
            Image(systemName: "arrow.left").font(.system(size: 12, weight: .light)).foregroundStyle(PilotTheme.accent.opacity(0.6)).offset(x: -64)
            Image(systemName: "arrow.right").font(.system(size: 12, weight: .light)).foregroundStyle(PilotTheme.accent.opacity(0.6)).offset(x: 64)
        }.accessibilityHidden(true)
    }
}
