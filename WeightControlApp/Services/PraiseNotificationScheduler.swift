import Foundation
import UserNotifications

/// ほめる通知の設定を保存するときのキー（`@AppStorage` / `UserDefaults` で使う名前）。
enum PraiseNotificationPreferenceKey {
    static let isEnabled = "praiseNotification.isEnabled"
}

/// 「ほめる通知」（週 1 回のふり返り・節目のお祝い）を、iPhone の通知センターに登録・削除する係。
///
/// 「いつ・どんな文面で出すか」は `PraiseNotificationPlanner`（Logic/）が決めます。
/// ここではその結果を UserNotifications（iOS の通知の仕組み）に渡すだけです。
/// 記録のリマインド（`WeighInReminderScheduler`）とは ID の先頭部分が違うので、お互いの通知を消し合いません。
/// 通知の許可は 1 つのアプリで共通なので、許可の確認には `WeighInReminderScheduler` のものを使います。
final class PraiseNotificationScheduler {
    static let shared = PraiseNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    /// 直前の作り直し処理。前の処理が終わってから次を始めるために覚えておきます
    /// （同時に走ると、消したはずの古い通知が残ることがあるため）。
    private var latestTask: Task<Void, Never>?

    private init() {}

    /// 設定と記録にあわせて、この先のほめる通知を作り直します。
    ///
    /// アプリを開いたとき、記録を追加・削除したとき、目標や設定を変えたときに呼びます。
    func update(isEnabled: Bool, points: [WeightPoint], goal: DashboardGoal?) {
        let previous = latestTask
        latestTask = Task {
            await previous?.value
            await apply(isEnabled: isEnabled, points: points, goal: goal)
        }
    }

    private func apply(isEnabled: Bool, points: [WeightPoint], goal: DashboardGoal?) async {
        await removePendingNotifications()
        guard isEnabled, await WeighInReminderScheduler.shared.isAuthorized() else { return }

        let calendar = Calendar.current
        let plans = PraiseNotificationPlanner.plan(points: points, goal: goal, now: .now, calendar: calendar)
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default

            // 「何年何月何日の何時何分」に 1 回だけ出す
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// まだ出ていない（予定の）ほめる通知を消します。
    /// すでに届いたお祝いは、通知センターに残しておきます（記録のリマインドと違い、残っていても困らないため）。
    private func removePendingNotifications() async {
        let prefix = PraiseNotificationPlanner.identifierPrefix
        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
    }
}
