import Foundation

/// 履歴の一覧で「前回からの増減」をどう見せるかを決めるロジック。
///
/// 体重は毎日上下するのがふつうなので、**増えたことを赤や警告で責めない** ようにしています。
/// - 目標の向きに動いた（減らしたい人が減った・増やしたい人が増えた）ときだけ、達成の色（緑）にする
/// - それ以外の動きは、目立たないグレー（`.secondary`）のまま
/// - 目標がない・キープが目標のときは、どちらに動いてもグレー
///
/// 色や SF Symbols の名前は画面側（SwiftUI）で決め、ここでは「どの種類か」だけを返します。
nonisolated struct WeightChangeStyle: Equatable, Sendable {
    /// 動いた向き
    enum Movement: Equatable, Sendable {
        case down
        case up
        /// 0.1 kg 未満の変化（表示上は ±0.0）
        case steady
    }

    /// 動いた向き
    var movement: Movement
    /// 目標の向きに動いたか（緑で表示する）
    var isTowardGoal: Bool

    /// 変化がこれより小さければ「変わらず」とみなす（kg）。表示は 0.1 kg 単位なので、その半分。
    static let steadyThresholdKg = 0.05

    /// 増減（kg）と目標の向きから、見せかたを決めます。
    ///
    /// - Parameters:
    ///   - changeKg: 前回からの増減（kg）。マイナスは減少。最初の記録は nil。
    ///   - direction: 目標の向き。目標がなければ nil。
    /// - Returns: 最初の記録（比べる相手がない）なら nil。
    static func classify(changeKg: Double?, direction: GoalDirection?) -> WeightChangeStyle? {
        guard let changeKg else { return nil }
        let movement: Movement
        if abs(changeKg) < steadyThresholdKg {
            movement = .steady
        } else {
            movement = changeKg < 0 ? .down : .up
        }

        let isTowardGoal: Bool = switch (direction, movement) {
        case (.lose?, .down), (.gain?, .up): true
        default: false
        }
        return WeightChangeStyle(movement: movement, isTowardGoal: isTowardGoal)
    }
}
