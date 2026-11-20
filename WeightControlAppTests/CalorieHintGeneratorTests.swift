import Foundation
import Testing
@testable import WeightControlApp

/// カロリーのオーバー分を食べ物に言いかえるロジック（CalorieHintGenerator）のテスト
struct CalorieHintGeneratorTests {

    // テスト用の小さな食品表（同梱の表を変えてもテストが壊れないように、自前で用意）
    private let apple = FoodItem(id: "apple", name: "りんご", unit: "個", portion: "中1個", kcal: 130, category: .fruit)
    private let banana = FoodItem(id: "banana", name: "バナナ", unit: "本", portion: "中1本", kcal: 90, category: .fruit)
    private let beer = FoodItem(id: "beer", name: "缶ビール", unit: "缶", portion: "350ml", kcal: 140, category: .alcohol)
    private let ramen = FoodItem(id: "ramen", name: "ラーメン", unit: "杯", portion: "1杯", kcal: 500, category: .dish)

    private var foods: [FoodItem] { [apple, banana, beer, ramen] }

    @Test("オーバーしていなければ目安どおり", arguments: [-300.0, 0, 49.9])
    func withinTarget(surplus: Double) {
        #expect(CalorieHintGenerator.hint(forSurplusKcal: surplus, foods: foods) == .withinTarget)
    }

    @Test("ありえない値（無限大・NaN）は目安どおり扱い", arguments: [Double.infinity, .nan])
    func nonFiniteIsWithinTarget(surplus: Double) {
        #expect(CalorieHintGenerator.hint(forSurplusKcal: surplus, foods: foods) == .withinTarget)
    }

    @Test("オーバー分にぴったりの食べ物を 1 個分で選ぶ")
    func picksExactSingleItem() {
        let hint = CalorieHintGenerator.hint(forSurplusKcal: 130, foods: foods)
        #expect(hint == .over(food: apple, count: 1, surplusKcal: 130))
        #expect(hint.foodPhrase == "りんご1個分")
    }

    @Test("候補から外した種類（お酒）は選ばない")
    func excludesCategories() {
        let hint = CalorieHintGenerator.hint(forSurplusKcal: 140, foods: foods, excluding: [.alcohol])
        #expect(hint == .over(food: apple, count: 1, surplusKcal: 140))
    }

    @Test("お酒を外さなければ、よりぴったりの缶ビールを選ぶ")
    func picksClosestMatch() {
        let hint = CalorieHintGenerator.hint(forSurplusKcal: 140, foods: foods)
        #expect(hint == .over(food: beer, count: 1, surplusKcal: 140))
    }

    @Test("2 個分などの整数個でも表せる")
    func multipleItems() {
        let hint = CalorieHintGenerator.hint(forSurplusKcal: 1000, foods: foods)
        #expect(hint == .over(food: ramen, count: 2, surplusKcal: 1000))
        #expect(hint.foodPhrase == "ラーメン2杯分")
    }

    @Test("半分は「半分」と言う")
    func halfPhrase() {
        let hint = CalorieHintGenerator.hint(forSurplusKcal: 60, foods: [banana])
        #expect(hint == .over(food: banana, count: 0.5, surplusKcal: 60))
        #expect(hint.foodPhrase == "バナナ半分")
    }

    @Test("1.5 個分は小数で言う")
    func fractionalPhrase() {
        let hint = CalorieHintGenerator.hint(forSurplusKcal: 135, foods: [banana])
        #expect(hint == .over(food: banana, count: 1.5, surplusKcal: 135))
        #expect(hint.foodPhrase == "バナナ1.5本分")
    }

    @Test("3 個分に収まらないほど多いときは、いちばん高カロリーの食べ物の整数個で表す")
    func veryLargeSurplus() {
        let hint = CalorieHintGenerator.hint(forSurplusKcal: 2600, foods: foods)
        #expect(hint == .over(food: ramen, count: 5, surplusKcal: 2600))
    }

    @Test("候補が空なら目安どおり扱い（クラッシュしない）")
    func emptyFoods() {
        #expect(CalorieHintGenerator.hint(forSurplusKcal: 300, foods: []) == .withinTarget)
    }

    @Test("メッセージは責めない言い方で、カロリーは 10kcal 単位に丸める")
    func messageText() {
        let hint = CalorieHint.over(food: apple, count: 1, surplusKcal: 134)
        #expect(hint.message == "今日は目安よりりんご1個分（約130kcal）多めでした。明日の食事ですこし調整すれば大丈夫です。")
        #expect(CalorieHint.withinTarget.message == "今日は目安どおりのカロリーです。いい調子です！")
        #expect(CalorieHint.withinTarget.foodPhrase == nil)
    }

    @Test("同梱の食品表でも、ふつうのオーバー分（50〜1500kcal）なら必ずヒントが出る")
    func worksWithBundledFoods() throws {
        let bundled = try FoodCatalog.loadBundledFoods()
        for surplus in stride(from: 50.0, through: 1500, by: 25) {
            let hint = CalorieHintGenerator.hint(forSurplusKcal: surplus, foods: bundled)
            guard case let .over(food, count, _) = hint else {
                Issue.record("\(surplus)kcal でヒントが出なかった")
                continue
            }
            // 言いかえた量が、元のオーバー分から大きくずれていない（±35% 以内）
            let ratio = food.kcal * count / surplus
            #expect((0.65...1.35).contains(ratio), "\(surplus)kcal → \(food.name) \(count)")
        }
    }
}
