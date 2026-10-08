import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("설정").font(.system(size: 24, weight: .semibold))
            Panel {
                VStack(spacing: 18) {
                    settingRow("마우스 스크롤 반전", detail: "트랙패드 방향은 유지됩니다.") {
                        Toggle("마우스 스크롤 반전", isOn: Binding(get: { store.configuration.reverseMouseScroll },
                            set: { store.setReverseMouseScroll($0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    Divider()
                    settingRow("로그인 시 실행", detail: "로그인하면 자동으로 시작합니다.") {
                        Toggle("로그인 시 실행", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }

            Text("권한").font(.system(size: 13, weight: .semibold))
            Panel {
                settingRow("손쉬운 사용", detail: store.permissions.isReady ? "허용됨" : "마우스 동작을 실행하려면 허용해 주세요.") {
                    if store.permissions.isReady {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(PilotTheme.accent)
                    } else {
                        Button("허용하기") { store.requestAccessibility() }.buttonStyle(AccentButtonStyle())
                    }
                }
            }
            if case .failed = store.engineStatus {
                HStack {
                    Text("마우스 연결을 확인해 주세요.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("다시 연결") { store.reconnect() }.buttonStyle(QuietButtonStyle())
                }
            }

            Panel {
                DisclosureGroup("고급 설정") {
                    VStack(spacing: 18) {
                        settingRow("키보드 단축키", detail: "Mac에 지정된 단축키를 확인합니다.") {
                            Button("설정 열기") { store.openKeyboardSettings() }.buttonStyle(QuietButtonStyle())
                        }
                        Divider()
                        settingRow("설정 파일", detail: "저장된 동작을 확인합니다.") {
                            Button("Finder에서 보기") { store.revealConfiguration() }.buttonStyle(QuietButtonStyle())
                        }
                        if !store.devices.isEmpty {
                            Divider()
                            HStack(alignment: .top) {
                                Text("연결된 마우스").font(.system(size: 12))
                                Spacer()
                                Text(store.devices.map(\.name).joined(separator: ", "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }.padding(.top, 18)
                }.font(.system(size: 12, weight: .medium))
            }

            Panel {
                DisclosureGroup("문제 해결") {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Text("진단 정보").font(.system(size: 12))
                            Spacer()
                            Button("복사") { store.copyDiagnostics() }.buttonStyle(QuietButtonStyle())
                        }
                        Divider()
                        settingRow("진단용 입력 기록", detail: "필요할 때만 켜세요. 끄면 기록이 지워집니다.") {
                            Toggle("진단용 입력 기록", isOn: Binding(get: { store.diagnosticsEnabled },
                                set: { store.setDiagnosticsEnabled($0) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                        if store.diagnosticsEnabled { DiagnosticsView(store: store) }
                        Text("권한을 허용했는데 연결되지 않으면 앱을 종료한 뒤, 손쉬운 사용 목록에 현재 앱을 다시 추가해 주세요.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    }.padding(.top, 18)
                }.font(.system(size: 12, weight: .medium))
            }
        }
    }

    private func settingRow<Control: View>(_ title: String, detail: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 15)
            control()
        }
    }
}
