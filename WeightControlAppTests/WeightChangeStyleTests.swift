import Testing
@testable import WeightControlApp

/// 履歴の増減の見せかた（WeightChangeStyle）のテスト
struct WeightChangeStyleTests {

    @Test("最初の記録（増減なし）は nil")
    func firstEntry() {
        #expect(WeightChangeStyle.classify(changeKg: nil, direction: .lose) == nil)
    }

    @Test("減らしたい人が減ったら、目標の向き（緑）")
    func loseGoalDown() {
        #expect(WeightChangeStyle.classify(changeKg: -0.3, direction: .lose)
                == WeightChangeStyle(movement: .down, isTowardGoal: true))
    }

    @Test("減らしたい人が増えても、責めない（目標の向きではないだけ）")
    func loseGoalUp() {
        #expect(WeightChangeStyle.classify(changeKg: 0.4, direction: .lose)
                == WeightChangeStyle(movement: .up, isTowardGoal: false))
    }

    @Test("増やしたい人が増えたら、目標の向き")
    func gainGoalUp() {
        #expect(WeightChangeStyle.classify(changeKg: 0.2, direction: .gain)
                == WeightChangeStyle(movement: .up, isTowardGoal: true))
        #expect(WeightChangeStyle.classify(changeKg: -0.2, direction: .gain)
                == WeightChangeStyle(movement: .down, isTowardGoal: false))
    }

    @Test("キープが目標・目標なしのときは、どちらに動いても色を付けない")
    func neutralWithoutDirection() {
        #expect(WeightChangeStyle.classify(changeKg: -0.5, direction: .maintain)?.isTowardGoal == false)
        #expect(WeightChangeStyle.classify(changeKg: -0.5, direction: nil)?.isTowardGoal == false)
        #expect(WeightChangeStyle.classify(changeKg: 0.5, direction: nil)?.movement == .up)
    }

    @Test("0.1 kg 未満の変化は「変わらず」で、目標の向きにも数えない")
    func steady() {
        #expect(WeightChangeStyle.classify(changeKg: 0, direction: .lose)
                == WeightChangeStyle(movement: .steady, isTowardGoal: false))
        #expect(WeightChangeStyle.classify(changeKg: -0.04, direction: .lose)?.movement == .steady)
        #expect(WeightChangeStyle.classify(changeKg: -0.1, direction: .lose)?.movement == .down)
    }
}
