import Foundation
import SwiftData

/// 体重の目標（目標体重と期限）。
///
/// アプリ内では「いまの目標」を 1 件だけ持ちます。目標を決め直したときは同じものを書き換えます。
/// 予測（フェーズ 3）や無理な目標のチェック（フェーズ 4）は、この値を Logic に渡して計算します。
@Model
final class WeightGoal {
    /// 目標体重（kg）
    var targetWeightKg: Double
    /// 期限（この日までに目標体重にしたい）
    var deadline: Date
    /// 目標を決めた日時
    var startDate: Date
    /// 目標を決めたときの体重（kg）。記録がまだなければ nil。進み具合の表示に使います。
    var startWeightKg: Double?
    /// 期限の決め方（Logic の `GoalPaceMode` の rawValue：ゆるやか・ハード・自分で決める）。
    /// 後から追加した列です。既定値（"manual"＝自分で決める）があるので、以前に保存した目標は
    /// 「自分で決めた期限」として読み込まれ、期限は変わりません。
    var paceModeRawValue: String = "manual"
    /// リバウンド抑制モード（Pro）を始めた日。nil ならモードではありません（docs/MAINTENANCE_MODE.md）。
    /// 後から追加した列です。既定値が nil なので、以前に保存した目標は「モードではない目標」として読み込まれます。
    /// モード中は `targetWeightKg` が範囲の中心になり、`deadline` は使いません。
    var maintenanceStartDate: Date? = nil
    /// リバウンド抑制モードの範囲の幅（中心からの片側、kg）。±1.5 kg なら 1.5。後から追加した列で、既定値は 1.5。
    var maintenanceHalfWidthKg: Double = 1.5

    init(
        targetWeightKg: Double,
        deadline: Date,
        startDate: Date = .now,
        startWeightKg: Double? = nil,
        paceModeRawValue: String = "manual",
        maintenanceStartDate: Date? = nil,
        maintenanceHalfWidthKg: Double = 1.5
    ) {
        self.targetWeightKg = targetWeightKg
        self.deadline = deadline
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.paceModeRawValue = paceModeRawValue
        self.maintenanceStartDate = maintenanceStartDate
        self.maintenanceHalfWidthKg = maintenanceHalfWidthKg
    }
}
