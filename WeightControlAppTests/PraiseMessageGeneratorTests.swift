import Foundation
import Testing
@testable import WeightControlApp

/// ほめるメッセージ（PraiseMessageGenerator）のテスト
struct PraiseMessageGeneratorTests {

    private func kinds(_ input: PraiseInput) -> [PraiseMessage.Kind] {
        PraiseMessageGenerator.messages(for: input).map(\.kind)
    }

    // MARK: - 連続記録

    @Test("記録したら毎回ほめる（1 日目）")
    func praisesFirstDay() {
        let message = PraiseMessageGenerator.primaryMessage(for: PraiseInput(streakDays: 1))
        #expect(message.kind == .streak(days: 1))
        #expect(message.text == "今日も記録できました！記録を続けることが、いちばんの近道です。")
    }

    @Test("節目の日数はお祝いのメッセージ", arguments: [3, 7, 14, 30, 50, 100, 200, 365])
    func streakMilestones(days: Int) {
        let message = PraiseMessageGenerator.primaryMessage(for: PraiseInput(streakDays: days))
        #expect(message.kind == .streakMilestone(days: days))
        #expect(message.text == "\(days)日連続で記録できました！すばらしい習慣になっています。")
    }

    @Test("節目以外の日数は「続いています」", arguments: [2, 4, 8, 99])
    func streakNonMilestone(days: Int) {
        let message = PraiseMessageGenerator.primaryMessage(for: PraiseInput(streakDays: days))
        #expect(message.kind == .streak(days: days))
        #expect(message.text == "\(days)日連続で記録できています。その調子です！")
    }

    @Test("記録が途切れていても責めず、再開をうながす")
    func restart() {
        let message = PraiseMessageGenerator.primaryMessage(for: PraiseInput(streakDays: 0))
        #expect(message.kind == .restart)
        #expect(message.text == "記録はいつからでも再開できます。今日の 1 回がいちばん大切です。")
    }

    // MARK: - トレンド

    @Test("減量中にトレンドが下がっていればほめる（いちばん先に出す）")
    func trendDownWhileLosing() {
        let input = PraiseInput(trendChangeKg: -0.54, streakDays: 5)
        let message = PraiseMessageGenerator.primaryMessage(for: input)
        #expect(message.kind == .trendTowardGoal(changeKg: -0.54))
        #expect(message.text == "トレンドが0.5kg下がっています。いい調子です！")
        #expect(kinds(input) == [.trendTowardGoal(changeKg: -0.54), .streak(days: 5)])
    }

    @Test("増量が目標なら、上がっていることをほめる")
    func trendUpWhileGaining() {
        let input = PraiseInput(trendChangeKg: 0.8, streakDays: 2, goalDirection: .gain)
        let message = PraiseMessageGenerator.primaryMessage(for: input)
        #expect(message.kind == .trendTowardGoal(changeKg: 0.8))
        #expect(message.text == "トレンドが0.8kg上がっています。いい調子です！")
    }

    @Test("変化が小さければ「安定しています」", arguments: [-0.19, 0, 0.19])
    func steadyTrend(change: Double) {
        let input = PraiseInput(trendChangeKg: change, streakDays: 2)
        #expect(kinds(input) == [.trendSteady, .streak(days: 2)])
    }

    @Test("減量中に増えても責めない。記録のほめ言葉を先に、はげましを後に出す")
    func gentleWhenNotDropping() {
        let input = PraiseInput(trendChangeKg: 0.6, streakDays: 4)
        let messages = PraiseMessageGenerator.messages(for: input)
        #expect(messages.map(\.kind) == [.streak(days: 4), .trendEncouragement])
        #expect(messages[1].text == "体重は水分や食事で日々上下するものです。記録を続けていれば、流れはちゃんと見えてきます。")
    }

    @Test("キープが目標なら、安定はほめる・動いたらはげます")
    func maintainGoal() {
        let steady = PraiseInput(trendChangeKg: 0.1, streakDays: 2, goalDirection: .maintain)
        #expect(PraiseMessageGenerator.primaryMessage(for: steady).text == "体重をしっかりキープできています。目標どおりです！")

        let drifted = PraiseInput(trendChangeKg: -0.7, streakDays: 2, goalDirection: .maintain)
        #expect(kinds(drifted) == [.streak(days: 2), .trendEncouragement])
    }

    @Test("トレンドのデータが足りなければ（nil）トレンドのメッセージは出さない")
    func noTrendData() {
        #expect(kinds(PraiseInput(trendChangeKg: nil, streakDays: 1)) == [.streak(days: 1)])
    }

    // MARK: - 目標の進み具合

    @Test("目標達成はいちばん先にお祝いする")
    func goalAchieved() {
        let input = PraiseInput(trendChangeKg: -0.3, streakDays: 30, goalProgress: 1.02)
        #expect(kinds(input) == [.goalAchieved, .streakMilestone(days: 30), .trendTowardGoal(changeKg: -0.3)])
        #expect(PraiseMessageGenerator.primaryMessage(for: input).text
                == "目標達成、おめでとうございます！ここまで続けてきた自分をほめてあげてください。")
    }

    @Test("半分を超えたら「半分を超えました」")
    func goalHalfway() {
        let input = PraiseInput(streakDays: 2, goalProgress: 0.5)
        #expect(kinds(input) == [.goalHalfway, .streak(days: 2)])
    }

    @Test("半分未満は % で伝える（切り捨て）")
    func goalPercent() {
        let messages = PraiseMessageGenerator.messages(for: PraiseInput(streakDays: 2, goalProgress: 0.239))
        #expect(messages.map(\.kind) == [.streak(days: 2), .goalProgress(percent: 23)])
        #expect(messages[1].text == "目標までの道のりの23%まで来ました！")
    }

    @Test("進み具合が 1% 未満・マイナスなら目標のメッセージは出さない", arguments: [0.0, 0.009, -0.2])
    func noGoalMessageWhenNotStarted(progress: Double) {
        #expect(kinds(PraiseInput(streakDays: 1, goalProgress: progress)) == [.streak(days: 1)])
    }

    // MARK: - 全体のルール

    @Test("どんな入力でも、メッセージは必ず 1 件以上あり、責める言葉を含まない")
    func neverBlames() {
        let blameWords = ["ダメ", "失敗", "サボ", "太りすぎ", "食べすぎ", "残念"]
        for trend in [-2.0, -0.5, 0, 0.5, 2.0, .nan] {
            for streak in [0, 1, 7, 12] {
                for progress in [nil, -0.5, 0.3, 0.7, 1.0] as [Double?] {
                    for direction in [GoalDirection.lose, .gain, .maintain] {
                        let input = PraiseInput(trendChangeKg: trend, streakDays: streak,
                                                goalProgress: progress, goalDirection: direction)
                        let messages = PraiseMessageGenerator.messages(for: input)
                        #expect(!messages.isEmpty)
                        for message in messages {
                            for word in blameWords {
                                #expect(!message.text.contains(word), "「\(message.text)」に「\(word)」")
                            }
                        }
                    }
                }
            }
        }
    }
}
