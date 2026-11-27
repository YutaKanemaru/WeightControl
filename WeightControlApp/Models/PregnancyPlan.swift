import Foundation
import SwiftData

/// 妊娠中モード 1 回分の設定（docs/PREGNANCY_MODE.md）。
///
/// 設定タブの「妊娠中モード」で始めると 1 件作られ、終えると `endedAt` に日時が入ります。
/// 終えたあとも記録として残し（グラフの印や「目標を立て直しましょう」のカードに使う）、次に始めるときは新しく 1 件作ります。
/// 前の目標（`WeightGoal`）は消さずにそのまま残すので、モードを終えたら目標を立て直せます。
///
/// 妊娠しているかどうかはとても大事な個人の情報なので、ほかのデータと同じく iPhone の中だけに保存し、外には送りません。
/// 妊娠前の BMI・区分・帯は保存せず、毎回計算します（身長を直したときにずれないため）。
@Model
final class PregnancyPlan {
    /// 出産予定日（その日の 0 時）
    var dueDate: Date
    /// 妊娠前の体重（kg）
    var prePregnancyWeightKg: Double
    /// 赤ちゃんが 2 人以上か
    var isMultiple: Bool
    /// 健診で言われた目安の下の値（出産までの合計、kg）。入れていなければ nil。
    var customGainLowKg: Double?
    /// 健診で言われた目安の上の値（出産までの合計、kg）。入れていなければ nil。入れたときは帯をこちらで描く。
    var customGainHighKg: Double?
    /// モードを始めた日時
    var startedAt: Date
    /// モードを終えた日時。nil ならモード中。
    var endedAt: Date?

    init(
        dueDate: Date,
        prePregnancyWeightKg: Double,
        isMultiple: Bool = false,
        customGainLowKg: Double? = nil,
        customGainHighKg: Double? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil
    ) {
        self.dueDate = dueDate
        self.prePregnancyWeightKg = prePregnancyWeightKg
        self.isMultiple = isMultiple
        self.customGainLowKg = customGainLowKg
        self.customGainHighKg = customGainHighKg
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    /// モード中か
    var isActive: Bool { endedAt == nil }
}

extension Array where Element == PregnancyPlan {
    /// モード中の 1 件（新しく始めたものを優先）。なければ nil。
    var activePlan: PregnancyPlan? {
        filter(\.isActive).max { $0.startedAt < $1.startedAt }
    }
}
