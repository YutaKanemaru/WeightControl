import SwiftUI
import UIKit

/// 設定画面の「通知」セクション：記録のリマインドのオン/オフと時刻。
///
/// ここでは設定値を `@AppStorage` に保存するだけです。
/// 実際の通知の作り直しは、`RootView` に付けた `weighInReminderSync()` が変化に気づいて行います。
struct ReminderSettingsSection: View {
    @AppStorage(ReminderPreferenceKey.isEnabled) private var isEnabled = false
    @AppStorage(ReminderPreferenceKey.hour) private var hour = ReminderTime.defaultTime.hour
    @AppStorage(ReminderPreferenceKey.minute) private var minute = ReminderTime.defaultTime.minute

    /// iOS の設定で通知が「許可しない」になっているか
    @State private var isDenied = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle("記録のリマインド", isOn: enabledBinding)

            if isEnabled {
                DatePicker("お知らせする時刻", selection: timeBinding, displayedComponents: .hourAndMinute)
            }

            if isDenied {
                Button("設定アプリで通知を許可する") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        } header: {
            Text("通知")
        } footer: {
            if isDenied {
                Text("iPhone の設定で、このアプリの通知が「許可しない」になっています。お知らせを受け取るには、設定アプリで許可してください。")
            } else {
                Text("毎日決まった時刻に、体重の記録をやさしくお知らせします。その日にもう記録していれば、お知らせはしません。")
            }
        }
        // 表示したときと、設定アプリから戻ってきたとき（scenePhase が変わったとき）に許可の状態を確かめる
        .task(id: scenePhase) {
            isDenied = await WeighInReminderScheduler.shared.isDenied()
        }
    }

    /// トグルをオンにしたときだけ、先に通知の許可を求める。許可されなければオフのまま。
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard newValue else {
                    isEnabled = false
                    return
                }
                Task {
                    let granted = await WeighInReminderScheduler.shared.requestAuthorization()
                    isEnabled = granted
                    isDenied = await WeighInReminderScheduler.shared.isDenied()
                }
            }
        )
    }

    /// DatePicker は `Date` を扱うので、保存している「時・分」と `Date` を相互に変換する
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let time = ReminderTime(hour: hour, minute: minute)
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour = parts.hour ?? ReminderTime.defaultTime.hour
                minute = parts.minute ?? ReminderTime.defaultTime.minute
            }
        )
    }
}

#Preview {
    List {
        ReminderSettingsSection()
    }
}
