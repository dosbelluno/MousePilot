import MousePilotCore
import SwiftUI

// This view exists only inside the explicitly enabled diagnostic session.
struct DiagnosticsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("전송: \(store.outputStatus)").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("지우기") { store.clearActivities() }.buttonStyle(.borderless).font(.system(size: 11))
            }
            if store.activities.isEmpty {
                Text("버튼을 누르면 여기에 표시됩니다.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.activities.prefix(12)) { activity in
                        HStack(spacing: 12) {
                            Text(activity.date, format: .dateTime.hour().minute().second())
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                            Text(activity.trigger.displayName).font(.system(size: 11))
                            Spacer()
                            Text(result(activity)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.padding(13).background(PilotTheme.raised, in: RoundedRectangle(cornerRadius: 9))
    }

    private func result(_ activity: MouseActivity) -> String {
        if activity.captured { return "버튼 확인" }
        if activity.waitingForGesture { return "대기" }
        if activity.gestureCancelled { return "취소" }
        return activity.action?.title ?? "기본 동작"
    }
}
