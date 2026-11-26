import Foundation

/// 目標の向き（減らしたいのか、増やしたいのか、キープしたいのか）
nonisolated enum GoalDirection: Sendable {
    case lose
    case gain
    case maintain
}

/// ほめるメッセージを作るための材料。画面や保存の仕組みには依存しない、ただの値です。
nonisolated struct PraiseInput: Equatable, Sendable {
    /// ここ最近のトレンド（EMA など、ならした体重）の変化（kg）。マイナスは減少。データが足りなければ nil。
    var trendChangeKg: Double?
    /// 連続記録日数（`WeighInStreakCalculator.currentStreak` の結果）
    var streakDays: Int
    /// 目標までの進み具合。0 = スタート時点、1 = 目標達成。目標がなければ nil。
    var goalProgress: Double?
    /// 目標の向き
    var goalDirection: GoalDirection = .lose
}

/// 画面に出すメッセージ 1 件分。
nonisolated struct PraiseMessage: Equatable, Sendable {
    /// メッセージの種類。画面側でアイコンや色を変えたいときに使えます。
    enum Kind: Equatable, Sendable {
        /// 目標達成
        case goalAchieved
        /// 連続記録の節目（3・7・14・30・50・100・200・365 日）
        case streakMilestone(days: Int)
        /// トレンドが目標の方向に動いている
        case trendTowardGoal(changeKg: Double)
        /// 目標まで半分を超えた
        case goalHalfway
        /// 体重が安定している
        case trendSteady
        /// 記録が続いている（節目以外）
        case streak(days: Int)
        /// 目標に向かって進んでいる（半分未満）
        case goalProgress(percent: Int)
        /// 体重が目標と逆に動いている。責めずに、続けることを応援する
        case trendEncouragement
        /// 記録が途切れている。再開をやさしく促す
        case restart
        /// キープモード：範囲の中でキープできている（`days` は範囲の中が続いている日数）
        case maintenanceKept(days: Int)
        /// キープモード：範囲の端に近づいた・外に出た。責めずに、戻し方をそえる
        case maintenanceDrift
    }

    var kind: Kind
    var text: String
}

/// 体重の変化・連続記録・目標の進み具合から、「ほめる」を優先したメッセージを作るロジック。
///
/// ルール:
/// - 記録したこと自体を必ずほめる（連続記録のメッセージは毎回出る）
/// - 体重が増えたときも責めない。日々の上下はふつうのことだと伝え、続けることを応援する
/// - 医療的な断定（「〜すれば必ずやせる」など）はしない
nonisolated enum PraiseMessageGenerator {
    /// これより小さいトレンドの変化（kg）は「安定」とみなす
    static let steadyThresholdKg: Double = 0.2

    /// 連続記録日数の「節目」
    static let streakMilestones: Set<Int> = [3, 7, 14, 30, 50, 100, 200, 365]

    /// いちばん伝えたいメッセージ 1 件（ホーム画面の一言などに）
    static func primaryMessage(for input: PraiseInput) -> PraiseMessage {
        // messages(for:) は必ず 1 件以上返す（連続記録 or 再開のメッセージが必ず入る）
        messages(for: input)[0]
    }

    /// 当てはまるメッセージを、伝えたい順（うれしいニュースが先）に並べて返します。
    static func messages(for input: PraiseInput) -> [PraiseMessage] {
        var result: [PraiseMessage] = [streakMessage(days: input.streakDays)]
        if let change = input.trendChangeKg, change.isFinite {
            result.append(trendMessage(changeKg: change, direction: input.goalDirection))
        }
        if let progress = input.goalProgress, progress.isFinite,
           let message = goalMessage(progress: progress) {
            result.append(message)
        }
        return result.sorted { priority(of: $0.kind) < priority(of: $1.kind) }
    }

    // MARK: - 各メッセージ

    private static func streakMessage(days: Int) -> PraiseMessage {
        switch days {
        case ...0:
            return PraiseMessage(kind: .restart,
                                 text: String(localized: "記録はいつからでも再開できます。今日の 1 回がいちばん大切です。"))
        case 1:
            return PraiseMessage(kind: .streak(days: 1),
                                 text: String(localized: "今日も記録できました！記録を続けることが、いちばんの近道です。"))
        case _ where streakMilestones.contains(days):
            return PraiseMessage(kind: .streakMilestone(days: days),
                                 text: String(localized: "\(days)日連続で記録できました！すばらしい習慣になっています。"))
        default:
            return PraiseMessage(kind: .streak(days: days),
                                 text: String(localized: "\(days)日連続で記録できています。その調子です！"))
        }
    }

    private static func trendMessage(changeKg: Double, direction: GoalDirection) -> PraiseMessage {
        let isSteady = abs(changeKg) < steadyThresholdKg

        // キープが目標なら、安定していること自体が成果
        if direction == .maintain {
            if isSteady {
                return PraiseMessage(kind: .trendTowardGoal(changeKg: changeKg),
                                     text: String(localized: "体重をしっかりキープできています。目標どおりです！"))
            }
            return encouragement
        }

        if isSteady {
            return PraiseMessage(kind: .trendSteady,
                                 text: String(localized: "体重は安定しています。続けていることが、次の変化の土台になります。"))
        }

        let isTowardGoal = (direction == .lose) == (changeKg < 0)
        guard isTowardGoal else { return encouragement }

        // 「トレンド」という言葉は使わず、「この 1 週間の流れ」と言いかえる（測った体重と別の数字があると迷うため）。
        // ホーム画面では 7 日前のトレンドと比べた変化を渡しています（HomeDashboardBuilder.trendChangeWindowDays）。
        let kgText = String(format: "%.1f", abs(changeKg))
        let text = direction == .lose
            ? String(localized: "この1週間の流れで\(kgText)kg下がっています。いい調子です！")
            : String(localized: "この1週間の流れで\(kgText)kg上がっています。いい調子です！")
        return PraiseMessage(kind: .trendTowardGoal(changeKg: changeKg), text: text)
    }

    private static var encouragement: PraiseMessage {
        PraiseMessage(kind: .trendEncouragement,
                      text: String(localized: "体重は水分や食事で日々上下するものです。記録を続けていれば、流れはちゃんと見えてきます。"))
    }

    private static func goalMessage(progress: Double) -> PraiseMessage? {
        if progress >= 1 {
            return PraiseMessage(kind: .goalAchieved,
                                 text: String(localized: "目標達成、おめでとうございます！ここまで続けてきた自分をほめてあげてください。"))
        }
        if progress >= 0.5 {
            return PraiseMessage(kind: .goalHalfway,
                                 text: String(localized: "目標までの道のりの半分を超えました！"))
        }
        // 切り捨てて % にする（0.01 未満は「まだ動いていない」ので出さない）
        let percent = Int((progress * 100).rounded(.down))
        guard percent >= 1 else { return nil }
        return PraiseMessage(kind: .goalProgress(percent: percent),
                             text: String(localized: "目標までの道のりの\(percent)%まで来ました！"))
    }

    // MARK: - 並び順

    /// 小さいほど先に出す。うれしいニュースを先に、はげましは後に。
    private static func priority(of kind: PraiseMessage.Kind) -> Int {
        switch kind {
        case .goalAchieved: 0
        case .streakMilestone: 1
        case .trendTowardGoal: 2
        case .goalHalfway: 3
        case .trendSteady: 4
        case .streak: 5
        case .goalProgress: 6
        case .trendEncouragement: 7
        case .restart: 8
        // キープモードのメッセージは MaintenanceAdvisor が作るので、ここでは並べない（念のため最後）
        case .maintenanceKept, .maintenanceDrift: 9
        }
    }
}
