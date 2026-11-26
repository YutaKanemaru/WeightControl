import Foundation
import Testing
@testable import WeightControlApp

/// ホームの「目標まで」（GoalDistanceCalculator）のテスト
struct GoalDistanceCalculatorTests {

    @Test("減らす目標で、まだ届いていなければ残りの kg")
    func loseToGo() {
        #expect(GoalDistanceCalculator.distance(latestKg: 67.0, targetKg: 65.0, startKg: 67.0) == .toGo(kg: 2.0))
    }

    @Test("67 kg から 65 kg を目指して 60 kg と入れたら、目標より 5.0 kg 下で達成")
    func loseBeyond() {
        #expect(
            GoalDistanceCalculator.distance(latestKg: 60.0, targetKg: 65.0, startKg: 67.0)
                == .beyond(kg: 5.0, isBelowGoal: true)
        )
    }

    @Test("差が 0.1 kg 以内なら達成")
    func reached() {
        #expect(GoalDistanceCalculator.distance(latestKg: 65.1, targetKg: 65.0, startKg: 67.0) == .reached)
        #expect(GoalDistanceCalculator.distance(latestKg: 64.95, targetKg: 65.0, startKg: 67.0) == .reached)
    }

    @Test("増やす目標で、目標より重くなったら目標より上で達成")
    func gainBeyond() {
        #expect(
            GoalDistanceCalculator.distance(latestKg: 56.0, targetKg: 55.0, startKg: 52.0)
                == .beyond(kg: 1.0, isBelowGoal: false)
        )
        #expect(GoalDistanceCalculator.distance(latestKg: 53.0, targetKg: 55.0, startKg: 52.0) == .toGo(kg: 2.0))
    }

    @Test("減らす目標なのに増えたときは、残りの kg（逆向きでも責めない）")
    func loseWrongDirection() {
        #expect(GoalDistanceCalculator.distance(latestKg: 68.3, targetKg: 65.0, startKg: 67.0) == .toGo(kg: 3.3))
    }

    @Test("スタート時の体重がわからなければ、差の大きさだけ")
    func unknownStart() {
        #expect(GoalDistanceCalculator.distance(latestKg: 60.0, targetKg: 65.0, startKg: nil) == .toGo(kg: 5.0))
    }

    @Test("小数の誤差が出ないよう 0.1 kg 単位に丸める")
    func rounding() {
        #expect(GoalDistanceCalculator.distance(latestKg: 65.3, targetKg: 65.1, startKg: 70.0) == .toGo(kg: 0.2))
    }
}
