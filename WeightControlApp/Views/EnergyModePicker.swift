import SwiftUI

/// 設定タブのプロフィール欄に出す「消費カロリーの計算」の選択。
///
/// `@Bindable` は「@Model のプロパティを、Picker などから直接書き換えられるようにする」しくみです。
/// 選んだ瞬間に `UserProfile` が書きかわり、ホームの摂取カロリーの目安も計算し直されます。
struct EnergyModePicker: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Picker("消費カロリーの計算", selection: $profile.energyMode) {
            ForEach(EnergyExpenditureMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.navigationLink)
    }
}

extension EnergyExpenditureMode {
    /// 画面に出す名前
    var title: LocalizedStringResource {
        switch self {
        case .automatic: "自動（おすすめ）"
        case .activityLevel: "プロフィールの活動量"
        case .healthKit: "ヘルスケアの実績"
        }
    }

    /// 画面に出す説明
    var detail: LocalizedStringResource {
        switch self {
        case .automatic: "ヘルスケアに 7 日分以上の運動データがあれば実績を、なければ活動量を使います。"
        case .activityLevel: "プロフィールで選んだ活動量から計算します。"
        case .healthKit: "ヘルスケアのアクティブエネルギーから計算します。データが 7 日分たまるまでは活動量を使います。"
        }
    }
}
