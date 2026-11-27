import SwiftUI
import SwiftData

/// 妊娠中モードの設定を保存するときのキー（`@AppStorage` / `UserDefaults` で使う名前）。
enum PregnancyPreferenceKey {
    /// 「前の目標に戻す」か、新しい目標を保存したときの、そのモードの終えた日時（`timeIntervalSinceReferenceDate`。0 ならまだ）
    static let resumedGoalEndedAt = "pregnancy.resumedGoalEndedAt"
    /// 「出産予定日をすぎました。続けますか？」で「続ける」を押したときの、そのモードの出産予定日（同じく 0 ならまだ）
    static let checkInDismissedDueDate = "pregnancy.checkInDismissedDueDate"
}

/// 画面から妊娠中モードの状態を決めるための道具。判断のルールは `PregnancyWeightGainGuide.modeState`（Logic）にあります。
enum PregnancyModeResolver {
    /// - Parameter resumedEndedAt: `PregnancyPreferenceKey.resumedGoalEndedAt` の値
    static func state(
        plans: [PregnancyPlan],
        profile: UserProfile?,
        goal: WeightGoal?,
        resumedEndedAt: Double
    ) -> PregnancyModeState {
        PregnancyWeightGainGuide.modeState(
            isFemale: profile?.sex == .female,
            hasActivePlan: plans.activePlan != nil,
            lastEndedAt: plans.compactMap(\.endedAt).max(),
            goalStartDate: goal?.startDate,
            resumedEndedAt: resumedEndedAt > 0 ? Date(timeIntervalSinceReferenceDate: resumedEndedAt) : nil
        )
    }

    /// いちばん最近に終えたモードの、終えた日時（`timeIntervalSinceReferenceDate`）。なければ 0。
    static func lastEndedAtValue(plans: [PregnancyPlan]) -> Double {
        plans.compactMap(\.endedAt).max()?.timeIntervalSinceReferenceDate ?? 0
    }
}

extension PregnancyPlan {
    /// ホームに出すもの（判断は `PregnancyAdvisor`）
    func dashboard(points: [WeightPoint], heightCm: Double, now: Date = .now) -> PregnancyDashboard {
        PregnancyAdvisor.evaluate(
            points: points,
            dueDate: dueDate,
            prePregnancyWeightKg: prePregnancyWeightKg,
            heightCm: heightCm,
            isMultiple: isMultiple,
            customLowKg: customGainLowKg,
            customHighKg: customGainHighKg,
            now: now
        )
    }
}

extension PrePregnancyBodyType {
    /// 画面での呼び方（「低体重」「肥満」などの区分の名前は使わない。docs/BMI_GOAL.md と同じ方針）
    var title: String {
        switch self {
        case .low: String(localized: "低め")
        case .normal: String(localized: "ふつう")
        case .high: String(localized: "高め")
        case .veryHigh: String(localized: "かなり高め")
        }
    }
}

/// 妊娠週数を「20 週 3 日」と表す
func gestationalAgeText(_ age: GestationalAge) -> Text {
    Text("\(age.weeks) 週 \(age.days) 日")
}

/// 妊娠中モードの免責の一文（ホーム・設定で使う）
struct PregnancyDisclaimerText: View {
    var body: some View {
        Text("妊娠中の目安は、日本産科婦人科学会（2021 年）などの公的な資料をもとにした一般的なものです。健診で医師・助産師から言われたことを優先してください。気になる変化があれば、健診を待たずにかかりつけの医療機関に相談してください。このアプリは医療アドバイスではありません。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
