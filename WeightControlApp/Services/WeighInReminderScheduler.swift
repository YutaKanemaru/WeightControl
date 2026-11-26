import Foundation
import UserNotifications

/// リマインド通知の設定を保存するときのキー（`@AppStorage` / `UserDefaults` で使う名前）。
///
/// 通知のオン/オフや時刻は「端末の設定」に近い小さな値なので、SwiftData ではなく
/// `UserDefaults`（アプリごとの小さな設定置き場。端末内に保存される）に入れています。
enum ReminderPreferenceKey {
    static let isEnabled = "weighInReminder.isEnabled"
    static let hour = "weighInReminder.hour"
    static let minute = "weighInReminder.minute"
}

/// 体重記録のリマインド通知を、iPhone の通知センターに登録・削除する係。
///
/// 「いつ・どんな文面で出すか」は `WeighInReminderPlanner`（Logic/）が決めます。
/// ここではその結果を UserNotifications（iOS の通知の仕組み）に渡すだけです。
/// 通知は端末の中だけで作られる「ローカル通知」で、サーバーは使いません。
final class WeighInReminderScheduler {
    static let shared = WeighInReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    /// 直前の作り直し処理。前の処理が終わってから次を始めるために覚えておきます
    /// （同時に走ると、消したはずの古い通知が残ることがあるため）。
    private var latestTask: Task<Void, Never>?

    private init() {}

    /// 通知の許可をユーザーに求めます（初回だけ iOS の確認ダイアログが出ます）。許可されたら true。
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// 通知が許可されているか。
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// まだ一度も通知の許可を聞いていないか（初回設定の「通知」のページを出すかに使う）。
    /// iOS の許可のダイアログはアプリで 1 回しか出せないので、もう答えている人にはページを出しません。
    func needsAuthorizationRequest() async -> Bool {
        await center.notificationSettings().authorizationStatus == .notDetermined
    }

    /// 通知が「許可しない」に設定されているか（このときはアプリからは許可を求め直せず、設定アプリで変える必要がある）。
    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// 設定と記録にあわせて、この先の通知を作り直します。
    ///
    /// アプリを開いたとき、記録を追加・削除したとき、設定を変えたときに呼びます。
    func update(isEnabled: Bool, time: ReminderTime, recordedDates: [Date]) {
        let previous = latestTask
        latestTask = Task {
            await previous?.value
            await apply(isEnabled: isEnabled, time: time, recordedDates: recordedDates)
        }
    }

    private func apply(isEnabled: Bool, time: ReminderTime, recordedDates: [Date]) async {
        await removeAllReminders()
        guard isEnabled, await isAuthorized() else { return }

        let calendar = Calendar.current
        let plans = WeighInReminderPlanner.plan(time: time, recordedDates: recordedDates, now: .now, calendar: calendar)
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

    /// このアプリのリマインド通知を、予定分も表示済みの分もすべて消します。
    private func removeAllReminders() async {
        let prefix = WeighInReminderPlanner.identifierPrefix
        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

        // 記録したあとに、通知センターに「記録しましょう」が残っていないように消しておく
        let deliveredIDs = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }
}
