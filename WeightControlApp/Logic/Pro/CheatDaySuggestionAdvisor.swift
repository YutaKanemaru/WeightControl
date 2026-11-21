import Foundation

/// チートデーの提案に使う目標（保存データ `WeightGoal` から画面側で詰め替えて渡します）。
nonisolated struct CheatDayGoal: Equatable, Sendable {
    /// 目標体重（kg）
    var targetWeightKg: Double
    /// 期限
    var deadline: Date
    /// 目標を決めた日
    var startDate: Date
    /// 目標を決めたときの体重（kg）。分からなければ nil（そのときは目標を決めた日以降の最初の記録を使います）。
    var startWeightKg: Double?
}

/// 「チートデーにしてよさそう」という提案の中身。
nonisolated struct CheatDaySuggestion: Equatable, Sendable {
    /// 予定の線より先に進んでいる量（貯金、kg）。プラスほど先に進んでいる。
    var aheadKg: Double
    /// 予定の線の、いちばん新しい記録の日の値（kg）
    var plannedWeightKg: Double
    /// 今の体重の目安（kg）。予測の直線の値。
    var currentWeightKg: Double
    /// これから 7 日（今日を含む）のうち、あと何日チートデーにできるか（1 か 2）
    var suggestedDays: Int
    /// チートデーの日に食べてよい量の目安（kcal）＝ 維持カロリー
    var cheatDayKcal: Double
    /// ふだんの日の目安（kcal）。チートデーにしても変わりません。
    var regularDayKcal: Double
    /// チートデー 1 日で貯金から使う量（kg）
    var costKgPerDay: Double
    /// チートデーにできる日（今日から 7 日以内、0 時にそろえたもの・古い順）
    var selectableDates: [Date]
}

/// 提案しなかった理由（画面には出しません。テストと、あとで理由を見たいとき用）。
nonisolated enum CheatDayNoSuggestionReason: Equatable, Sendable {
    /// 減量の目標ではない（増量・キープ）
    case notLosingGoal
    /// 開始の体重が分からない
    case missingStartWeight
    /// もう目標に届いている
    case goalReached
    /// 記録が足りない（直近 21 日に 7 日未満）
    case tooFewRecords(recordedDays: Int)
    /// このペースだと期限に間に合わない（または期限を過ぎた）
    case notOnTrack
    /// 予定の線より 0.5 kg 以上先に進んでいない（すでに決めたチートデーの分を引いたあと）
    case notAheadEnough(aheadKg: Double)
    /// 目安がすでに維持カロリーと同じで、チートデーにしても差がない
    case noDifference
    /// 週 2 日までの決まりで、これから 7 日に選べる日がない
    case weeklyLimitReached
}

/// 提案するかどうかの結果。
nonisolated enum CheatDaySuggestionResult: Equatable, Sendable {
    case suggested(CheatDaySuggestion)
    case notSuggested(CheatDayNoSuggestionReason)

    /// 提案があればその中身
    var suggestion: CheatDaySuggestion? {
        if case .suggested(let suggestion) = self { return suggestion }
        return nil
    }
}

/// チートデーを提案するかどうかを、端末の中のルールで決めます（Pro 機能・フェーズ 12）。仕様は docs/CHEAT_DAY.md。
///
/// ## 考え方
/// 1. 目標を決めた日の体重から、期限の目標体重まで、まっすぐ下がる線を **予定の線** とする
/// 2. 予測の直線（`GoalForecaster.paceEstimate`）の今の値と比べて、予定より何 kg 先に進んでいるか（**貯金**）を出す
/// 3. 貯金が 0.5 kg 以上・記録 7 日以上・期限に間に合う見込みなど、条件をすべて満たすときだけ提案する
///
/// チートデーの量は **維持カロリー（体重が増えも減りもしない量）まで** で、ほかの日は今までどおりです。
/// 先に進んでいる分（貯金）でまかなうので、ほかの日を控えめにする必要はありません。
///
/// クラウドの AI は使いません（体重のデータを外に送らないため）。ルールなので、なぜ提案したかを数字で説明できます。
nonisolated enum CheatDaySuggestionAdvisor {
    /// 予定より何 kg 先に進んでいたら提案するか
    static let minimumAheadKg = 0.5
    /// 提案に必要な記録日数（直近 21 日のうち）。予測が「精度は低め」の間は出さない。
    static let minimumRecordedDays = GoalForecaster.reliableRecordedDays
    /// どの 7 日間でも、チートデーはこの日数まで
    static let maximumDaysPerWeek = 2
    /// 1 週間の日数（提案で選べるのは今日から何日分か）
    static let daysPerWeek = 7
    /// 体脂肪 1 kg あたりのエネルギー（kcal）
    static let kcalPerKg = 7200.0
    /// これより小さい差なら「目標＝キープ」とみなす（kg）
    static let maintainToleranceKg = 0.1

    /// - Parameters:
    ///   - points: 体重の記録（順番はバラバラで OK）
    ///   - goal: いまの目標
    ///   - forecast: 同じ記録・目標で計算した予測（`GoalForecaster.forecast` の結果）
    ///   - intake: 1 日の摂取カロリーの目安（`targetKcal` がふだんの日、`tdeeKcal` が維持カロリー）
    ///   - cheatDays: すでにチートデーにした日（過去・未来どちらも。時刻は無視します）
    ///   - now: 今の日時
    static func suggest(
        points: [WeightPoint],
        goal: CheatDayGoal,
        forecast: GoalForecast,
        intake: IntakeRecommendation,
        cheatDays: [Date],
        now: Date,
        calendar: Calendar = .current
    ) -> CheatDaySuggestionResult {
        // 開始の体重：保存してある値。なければ目標を決めた日以降の最初の記録
        let startDay = calendar.startOfDay(for: goal.startDate)
        guard let startKg = goal.startWeightKg
            ?? points.filter({ calendar.startOfDay(for: $0.date) >= startDay }).min(by: { $0.date < $1.date })?.weightKg
        else { return .notSuggested(.missingStartWeight) }

        // 減量の目標だけ
        guard startKg - goal.targetWeightKg > maintainToleranceKg else { return .notSuggested(.notLosingGoal) }

        // もう届いている
        let currentKg = forecast.currentWeightKg
        guard currentKg - goal.targetWeightKg > GoalForecaster.reachedToleranceKg else { return .notSuggested(.goalReached) }

        // 予測の精度が低い間は出さない
        guard forecast.recordedDays >= minimumRecordedDays else {
            return .notSuggested(.tooFewRecords(recordedDays: forecast.recordedDays))
        }

        // このペースで期限に間に合う見込みのときだけ
        guard forecast.deadlineStatus == .onTrack else { return .notSuggested(.notOnTrack) }

        // チートデーにしても食べる量が変わらないなら、提案する意味がない
        let extraKcal = intake.tdeeKcal - intake.targetKcal
        guard extraKcal > 0 else { return .notSuggested(.noDifference) }
        let costKg = extraKcal / kcalPerKg

        // 予定の線（いちばん新しい記録の日の値）と貯金
        let plannedKg = plannedWeight(
            startKg: startKg,
            targetKg: goal.targetWeightKg,
            startDate: goal.startDate,
            deadline: goal.deadline,
            on: forecast.latestDate,
            calendar: calendar
        )
        let aheadKg = plannedKg - currentKg

        // これから 7 日にすでに決めたチートデーは、まだ体重に表れていないので貯金から先に引いておく
        let today = calendar.startOfDay(for: now)
        let cheatDaySet = Set(cheatDays.map { calendar.startOfDay(for: $0) })
        let upcomingCount = cheatDaySet.filter {
            let offset = DayMath.days(from: today, to: $0, calendar: calendar)
            return (0..<daysPerWeek).contains(offset)
        }.count
        let aheadAfterPlannedKg = aheadKg - Double(upcomingCount) * costKg
        guard aheadAfterPlannedKg >= minimumAheadKg else {
            return .notSuggested(.notAheadEnough(aheadKg: aheadAfterPlannedKg))
        }

        // 選べる日：今日から 7 日のうち、まだチートデーでなく、どの 7 日間でも 2 日を超えない日
        let selectable = (0..<daysPerWeek)
            .map { DayMath.date(byAddingDays: $0, to: today, calendar: calendar) }
            .filter { !cheatDaySet.contains($0) && canAdd($0, to: cheatDaySet, calendar: calendar) }
        let remainingByLimit = maximumDaysPerWeek - upcomingCount
        guard !selectable.isEmpty, remainingByLimit > 0 else { return .notSuggested(.weeklyLimitReached) }

        // 2 日使っても貯金が 0.5 kg 以上残るなら 2 日まで、そうでなければ 1 日
        let affordsTwo = aheadAfterPlannedKg - 2 * costKg >= minimumAheadKg
        let days = min(affordsTwo ? 2 : 1, remainingByLimit, selectable.count)

        return .suggested(CheatDaySuggestion(
            aheadKg: aheadKg,
            plannedWeightKg: plannedKg,
            currentWeightKg: currentKg,
            suggestedDays: days,
            cheatDayKcal: intake.tdeeKcal,
            regularDayKcal: intake.targetKcal,
            costKgPerDay: costKg,
            selectableDates: selectable
        ))
    }

    /// 予定の線の `date` の日の値（kg）。開始日より前は開始の体重、期限より後は目標体重。
    static func plannedWeight(
        startKg: Double,
        targetKg: Double,
        startDate: Date,
        deadline: Date,
        on date: Date,
        calendar: Calendar = .current
    ) -> Double {
        let totalDays = DayMath.days(from: startDate, to: deadline, calendar: calendar)
        guard totalDays > 0 else { return targetKg }
        let elapsed = min(max(DayMath.days(from: startDate, to: date, calendar: calendar), 0), totalDays)
        return startKg - (startKg - targetKg) * Double(elapsed) / Double(totalDays)
    }

    /// `day` をチートデーに足しても、`day` を含むどの 7 日間でも 2 日以内に収まるか
    static func canAdd(_ day: Date, to cheatDays: Set<Date>, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        // `day` を含む 7 日間は、`day` の 6 日前から始まるもの〜`day` から始まるもの、の 7 とおり
        for startOffset in -(daysPerWeek - 1)...0 {
            let windowStart = DayMath.date(byAddingDays: startOffset, to: target, calendar: calendar)
            let count = cheatDays.filter {
                let offset = DayMath.days(from: windowStart, to: $0, calendar: calendar)
                return (0..<daysPerWeek).contains(offset) && $0 != target
            }.count
            if count + 1 > maximumDaysPerWeek { return false }
        }
        return true
    }

    /// その日がチートデーか（今日の摂取カロリーの目安を維持カロリーで出すかどうかに使います）
    static func isCheatDay(_ date: Date, cheatDays: [Date], calendar: Calendar = .current) -> Bool {
        cheatDays.contains { calendar.isDate($0, inSameDayAs: date) }
    }
}
