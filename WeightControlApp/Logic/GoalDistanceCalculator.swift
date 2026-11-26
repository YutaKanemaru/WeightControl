import Foundation

/// ホームの体重のカードに出す「目標まで」の状態。
nonisolated enum GoalDistance: Equatable, Sendable {
    /// まだ目標に届いていない。あと何 kg か（いつもプラス）。
    case toGo(kg: Double)
    /// 目標との差が 0.1 kg 以内
    case reached
    /// 目標を通りこした。目標よりどれだけ先か（いつもプラス）と、どちら側か。
    case beyond(kg: Double, isBelowGoal: Bool)
}

/// 「目標まで」を、最新の体重（測った数字そのまま）から計算します。
///
/// 同じカードの大きな数字（最新の体重）と同じ基準にして、見たとおりに分かるようにするためです。
/// 予報やカロリーは、1 日のブレに強い「今の体重の目安」（直近 3 週間の直線の今日の値）のままです。
/// 詳しくは docs/WEIGHT_RECORDS.md。
nonisolated enum GoalDistanceCalculator {
    /// 目標との差がこれ以下なら「達成」とみなす（kg）
    static let reachedToleranceKg = 0.1

    /// - Parameters:
    ///   - latestKg: いちばん新しい記録の体重（kg）
    ///   - targetKg: 目標体重（kg）
    ///   - startKg: 目標を決めたときの体重（kg）。目標の向き（減らす・増やす）を決めるのに使う。
    ///     わからなければ nil（そのときは通りこしたかを判断せず、差の大きさだけを出す）。
    static func distance(latestKg: Double, targetKg: Double, startKg: Double?) -> GoalDistance {
        let diff = latestKg - targetKg  // プラスなら目標より重い
        if abs(diff) <= reachedToleranceKg { return .reached }

        let direction = startKg.map { HomeDashboardBuilder.goalDirection(startKg: $0, targetKg: targetKg) } ?? .maintain
        switch direction {
        case .lose where diff < 0:
            return .beyond(kg: rounded(-diff), isBelowGoal: true)
        case .gain where diff > 0:
            return .beyond(kg: rounded(diff), isBelowGoal: false)
        case .lose, .gain, .maintain:
            return .toGo(kg: rounded(abs(diff)))
        }
    }

    /// 小数第 1 位に丸める（小数の誤差で 5.000000001 のようにならないように）
    private static func rounded(_ kg: Double) -> Double {
        (kg * 10).rounded() / 10
    }
}
