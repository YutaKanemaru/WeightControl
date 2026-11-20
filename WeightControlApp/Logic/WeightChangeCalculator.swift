import Foundation

/// 体重の推移を計算するときに使う、シンプルな「日付と体重」の組。
/// SwiftData の `WeightEntry` を直接使わないことで、ロジックを画面や保存の仕組みから切り離しています。
nonisolated struct WeightPoint: Equatable, Sendable {
    var date: Date
    var weightKg: Double
}

nonisolated enum WeightChangeCalculator {
    /// それぞれの記録について「ひとつ前（日付が直前）の記録からの増減（kg）」を返します。
    ///
    /// - 戻り値の並びは引数 `points` と同じ順番です。
    /// - いちばん古い記録には比べる相手がいないので `nil` です。
    /// - 結果は小数第 1 位に丸めます（0.1 + 0.2 のような小数の誤差で 0.30000000004 と表示されないように）。
    static func changesFromPrevious(_ points: [WeightPoint]) -> [Double?] {
        // 日付の古い順に並べた「元の位置（インデックス）」の一覧
        let chronological = points.indices.sorted { points[$0].date < points[$1].date }

        var result = [Double?](repeating: nil, count: points.count)
        for (order, index) in chronological.enumerated() where order > 0 {
            let previous = points[chronological[order - 1]]
            let diff = points[index].weightKg - previous.weightKg
            result[index] = (diff * 10).rounded() / 10
        }
        return result
    }
}
