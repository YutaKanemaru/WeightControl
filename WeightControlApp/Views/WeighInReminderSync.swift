import SwiftUI
import SwiftData

/// 記録や設定が変わったら、リマインド通知を自動で作り直す仕組み（ViewModifier）。
///
/// `ViewModifier` は「画面に後から機能を足す部品」です。`RootView` に 1 行付けておくだけで、
/// どの画面で記録を追加・削除しても、ここが変化に気づいて通知を作り直します。
/// こうしておくと、記録画面や履歴画面に通知のコードを書かずにすみます。
struct WeighInReminderSync: ViewModifier {
    @Query private var entries: [WeightEntry]
    /// アプリが前面にあるか、裏に回ったか（scenePhase）。前面に戻るたびに日付が変わっている可能性があるので作り直す
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ReminderPreferenceKey.isEnabled) private var isEnabled = false
    @AppStorage(ReminderPreferenceKey.hour) private var hour = ReminderTime.defaultTime.hour
    @AppStorage(ReminderPreferenceKey.minute) private var minute = ReminderTime.defaultTime.minute

    /// これらのどれかが変わったら作り直す
    private struct Trigger: Equatable {
        var recordedDates: [Date]
        var isEnabled: Bool
        var hour: Int
        var minute: Int
        var isActive: Bool
    }

    func body(content: Content) -> some View {
        content
            // .task(id:) は、画面が表示されたときと、id の値が変わったときに中身を実行します
            .task(id: Trigger(recordedDates: entries.map(\.date),
                              isEnabled: isEnabled,
                              hour: hour,
                              minute: minute,
                              isActive: scenePhase == .active)) {
                WeighInReminderScheduler.shared.update(
                    isEnabled: isEnabled,
                    time: ReminderTime(hour: hour, minute: minute),
                    recordedDates: entries.map(\.date)
                )
            }
    }
}

extension View {
    /// 記録や設定の変化にあわせて、リマインド通知を作り直します。
    func weighInReminderSync() -> some View {
        modifier(WeighInReminderSync())
    }
}
