import SwiftUI
import UIKit

/// 設定画面の「通知」セクション：記録のリマインドのオン/オフと時刻、ほめる通知のオン/オフ。
///
/// ここでは設定値を `@AppStorage` に保存するだけです。
/// 実際の通知の作り直しは、`RootView` に付けた `weighInReminderSync()` が変化に気づいて行います。
struct ReminderSettingsSection: View {
    @AppStorage(ReminderPreferenceKey.isEnabled) private var isEnabled = false
    @AppStorage(ReminderPreferenceKey.hour) private var hour = ReminderTime.defaultTime.hour
    @AppStorage(ReminderPreferenceKey.minute) private var minute = ReminderTime.defaultTime.minute
    @AppStorage(PraiseNotificationPreferenceKey.isEnabled) private var isPraiseEnabled = false

    /// iOS の設定で通知が「許可しない」になっているか
    @State private var isDenied = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                Label("記録のリマインド", systemImage: "bell")
            }

            if isEnabled {
                DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
                    Label("お知らせする時刻", systemImage: "clock")
                }
            }

            Toggle(isOn: praiseEnabledBinding) {
                Label("ほめる通知", systemImage: "hands.clap")
            }

            if isDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("設定アプリで通知を許可する", systemImage: "gear")
                }
            }
        } header: {
            Text("通知")
        } footer: {
            if isDenied {
                NoticeLabel("iPhone の設定で、このアプリの通知が「許可しない」になっています。お知らせを受け取るには、設定アプリで許可してください。", style: .caution)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("記録のリマインド：毎日決まった時刻に、体重の記録をやさしくお知らせします。その日にもう記録していれば、お知らせはしません。")
                    Text("ほめる通知：毎週日曜の夜に 1 週間のふり返りを、連続記録や目標までの道のりの節目に届いた日の夜にお祝いをお届けします。")
                }
            }
        }
        // 表示したときと、設定アプリから戻ってきたとき（scenePhase が変わったとき）に許可の状態を確かめる
        .task(id: scenePhase) {
            isDenied = await WeighInReminderScheduler.shared.isDenied()
        }
    }

    private var enabledBinding: Binding<Bool> {
        authorizingBinding(for: $isEnabled)
    }

    private var praiseEnabledBinding: Binding<Bool> {
        authorizingBinding(for: $isPraiseEnabled)
    }

    /// トグルをオンにしたときだけ、先に通知の許可を求める。許可されなければオフのまま。
    /// （通知の許可はアプリで 1 つなので、どちらのトグルから許可しても、もう片方にも効きます）
    private func authorizingBinding(for value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                guard newValue else {
                    value.wrappedValue = false
                    return
                }
                Task {
                    let granted = await WeighInReminderScheduler.shared.requestAuthorization()
                    value.wrappedValue = granted
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

#Preview("大きい文字・ダークモード") {
    List {
        ReminderSettingsSection()
    }
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}
