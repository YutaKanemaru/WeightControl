import Foundation

/// 「目安カロリーより何 kcal 多かったか」を、身近な食べ物の量に言いかえた結果。
nonisolated enum CalorieHint: Equatable, Sendable {
    /// 目安どおり（または目安より少ない）
    case withinTarget
    /// 目安より多め。`count` 個（0.5 刻み）の `food` くらい。`surplusKcal` は元のオーバー分。
    case over(food: FoodItem, count: Double, surplusKcal: Double)

    /// 食べ物の量だけを表す短い言い方（例: "りんご1個分"、"バナナ半分"）。目安どおりなら nil。
    var foodPhrase: String? {
        guard case let .over(food, count, _) = self else { return nil }
        return Self.phrase(food: food, count: count)
    }

    /// 画面や通知にそのまま出せる、責めない言い方のメッセージ。
    var message: String {
        switch self {
        case .withinTarget:
            return String(localized: "今日は目安どおりのカロリーです。いい調子です！")
        case let .over(food, count, surplusKcal):
            let phrase = Self.phrase(food: food, count: count)
            // 細かすぎる数字は気になるので、10kcal 単位に丸めて「約」をつける
            let roundedKcal = Int((surplusKcal / 10).rounded() * 10)
            return String(localized: "今日は目安より\(phrase)（約\(roundedKcal)kcal）多めでした。明日の食事ですこし調整すれば大丈夫です。")
        }
    }

    private static func phrase(food: FoodItem, count: Double) -> String {
        if count == 0.5 {
            return String(localized: "\(food.name)半分")
        }
        // 1.0 → "1"、1.5 → "1.5" のように、必要なときだけ小数を出す
        let countText = count == count.rounded() ? String(Int(count)) : String(format: "%.1f", count)
        return String(localized: "\(food.name)\(countText)\(food.unit)分")
    }
}

/// カロリーのオーバー分（kcal）を、食品表の中から「ちょうどいい食べ物と個数」に言いかえるロジック。
///
/// 例: 140kcal オーバー → 「缶ビール1缶分」、65kcal → 「バナナ半分」くらい。
/// 摂取カロリーの計算（別の Logic）とは切り離して、結果の数字（Double）だけを受け取ります。
nonisolated enum CalorieHintGenerator {
    /// これ未満のオーバーは「誤差の範囲」とみなして、目安どおり扱いにします（kcal）。
    static let defaultToleranceKcal: Double = 50

    /// 使う個数の候補（0.5 個刻みで 3 個まで）。「りんご 7.5 個分」のような分かりにくい言い方を避けるため。
    static let countRange: ClosedRange<Double> = 0.5...3

    /// オーバー分を食べ物の量に言いかえます。
    ///
    /// - Parameters:
    ///   - surplusKcal: 目安カロリーを超えた量（kcal）。0 以下なら目安どおり。
    ///   - foods: 候補の食品（ふつうは `FoodCatalog.loadBundledFoods()` の結果）
    ///   - excluding: 候補から外す種類（例: お酒を飲まない人には `[.alcohol]`）
    ///   - toleranceKcal: これ未満なら目安どおりとみなす
    static func hint(
        forSurplusKcal surplusKcal: Double,
        foods: [FoodItem],
        excluding excludedCategories: Set<FoodCategory> = [],
        toleranceKcal: Double = defaultToleranceKcal
    ) -> CalorieHint {
        guard surplusKcal.isFinite, surplusKcal >= toleranceKcal else { return .withinTarget }

        let candidates = foods.filter { $0.kcal > 0 && !excludedCategories.contains($0.category) }
        guard !candidates.isEmpty else { return .withinTarget }

        // 1) 0.5〜3 個の範囲で、オーバー分にいちばん近くなる食べ物を探す
        var best: (food: FoodItem, count: Double, score: Double)?
        for food in candidates {
            let count = (surplusKcal / food.kcal * 2).rounded() / 2 // 0.5 刻みに丸める
            guard countRange.contains(count) else { continue }

            // 実際のオーバー分とのズレ（割合）。小さいほど良い。
            var score = abs(count * food.kcal - surplusKcal) / surplusKcal
            // 「1個分」がいちばん想像しやすいので少し優先し、半端な数（1.5 など）は少し避ける
            if count != 1 { score += 0.12 }
            if count != count.rounded() { score += 0.05 }

            // 同点なら食品表で先に書かれているものを優先（結果が毎回同じになるように）
            if let current = best, current.score <= score { continue }
            best = (food, count, score)
        }
        if let best {
            return .over(food: best.food, count: best.count, surplusKcal: surplusKcal)
        }

        // 2) オーバー分が大きすぎて 3 個に収まらないときは、いちばんカロリーの高い食べ物の整数個で表す
        let biggest = candidates.max { $0.kcal < $1.kcal }!
        let count = max(1, (surplusKcal / biggest.kcal).rounded())
        return .over(food: biggest, count: count, surplusKcal: surplusKcal)
    }
}
