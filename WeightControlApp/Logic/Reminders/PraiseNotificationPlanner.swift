import Foundation

/// 登録する予定の「ほめる通知」1 件分。通知の仕組み（UserNotifications）には依存しない、ただの値です。
nonisolated struct PlannedPraiseNotification: Equatable, Sendable {
    /// 通知の種類
    enum Kind: Equatable, Sendable {
        /// 週 1 回のふり返り。`recordedDays` はその週（7 日間）に記録できた日数。
        /// 同じ日に節目にも届いていれば `milestone` に入ります（1 通にまとめるため）。
        case weeklyRecap(recordedDays: Int, milestone: PraiseMilestone?)
        /// 節目に届いたお祝い
        case milestone(PraiseMilestone)
        /// リバウンド抑制モード（Pro）：範囲から出た・範囲に戻った
        case maintenance(MaintenanceAdvisor.Crossing)
    }

    /// 通知の ID（例: `praiseNotification.weeklyRecap.2026-11-22`）。同じ ID で登録し直すと上書きされます。
    var identifier: String
    /// 通知を出す日時
    var fireDate: Date
    var kind: Kind
    var title: String
    var body: String
}

/// その日に届いた「節目」。
nonisolated struct PraiseMilestone: Equatable, Sendable {
    /// 連続記録日数の節目（3・7・14・30… 日）。届いていなければ nil。
    var streakDays: Int?
    /// 目標までの道のりの節目（25・50・75・100 %）。届いていなければ nil。
    var goalPercent: Int?
}

/// 「ほめる通知」を、いつ・どんな文面で出すかを決めるロジック。
///
/// 通知は 2 種類です（どちらも「その日の夜 20:00」に出します）。
/// 1. **週 1 回のふり返り**：毎週日曜の夜に「この 1 週間で 5 日記録できました」。1 日も記録がない週は出しません（責めないため）。
/// 2. **節目のお祝い**：連続記録（7 日連続など）や、目標までの道のりの 25/50/75/100% に届いた日の夜に 1 通。
///    節目に届いた記録が夜 20:00 より後なら、次の日の夜に出します。
///    日曜（ふり返りの日）に節目に届いたときは、ふり返りの 1 通にまとめます。
/// 3. **リバウンド抑制モード（Pro）**：範囲から出た日・範囲に戻った日の夜に 1 通ずつ（docs/MAINTENANCE_MODE.md）。
///    モード中は目標の節目（25/50/75/100%）は出さず、ふり返りに「範囲の中でキープできました」をそえます。
///    Pro を使えないときは、呼ぶ側が目標からモードの情報を外して渡します（`WeightGoal.dashboardGoal(includesMaintenance:)`）。
///
/// ## なぜ「その日の夜」にするのか
/// 節目に届くのは記録した瞬間なので、そのときはアプリの中でほめています。
/// 夜にもう一度お祝いが届くと、1 日のおわりに「今日もできた」とふり返るきっかけになります。
///
/// ## 何も覚えておかなくても、同じお祝いを二度出さないしくみ
/// - 節目は「今日」か「昨日」に届いたものだけを見ます。通知を出す時刻を過ぎたものは登録しません。
/// - 目標の節目は、それより前の日に一度でも届いていたら、もう一度は出しません
///   （体重が上下して 50% を行ったり来たりしても、お祝いは 1 回だけ）。
///
/// 体重の目安は、ホーム画面と同じ `HomeDashboardBuilder.currentWeightEstimate`（直近 3 週間の直線）を使うので、
/// ホームの表示と通知の % がずれません。
nonisolated enum PraiseNotificationPlanner {
    /// このアプリのほめる通知であることを示す ID の先頭部分
    static let identifierPrefix = "praiseNotification."
    /// 通知を出す時刻（夜 20:00）。1 日のおわりにふり返れる時間にしています。
    static let eveningTime = ReminderTime(hour: 20, minute: 0)
    /// ふり返りを出す曜日（`Calendar` の曜日番号。1 = 日曜）
    static let recapWeekday = 1
    /// ふり返りで数える日数（通知を出す日を含めた 7 日間）
    static let recapDays = 7
    /// 目標までの道のりの節目（%）
    static let goalMilestonePercents = [25, 50, 75, 100]

    /// これから登録する通知の一覧を、日時の早い順に返します。
    ///
    /// - Parameters:
    ///   - points: 体重の記録（順番はバラバラで OK）
    ///   - goal: いまの目標。なければ nil（目標の節目は出しません）
    ///   - heightCm: 身長（リバウンド抑制モードの範囲の下の端を BMI 18.5 で止めるため。ホームと同じ範囲にする）
    ///   - now: 「今」とみなす日時。テストで日付を固定できるように引数にしています。
    ///   - calendar: 日付の区切り（タイムゾーン）と曜日を決めるカレンダー
    static func plan(
        points: [WeightPoint],
        goal: DashboardGoal?,
        heightCm: Double? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedPraiseNotification] {
        // リバウンド抑制モード中なら、その範囲と始めた日
        let maintenance: (range: MaintenanceRange, startDate: Date)? = goal.flatMap { goal in
            goal.maintenanceStartDate.map { start in
                (range: MaintenanceAdvisor.range(centerKg: goal.targetWeightKg, halfWidthKg: goal.maintenanceHalfWidthKg, heightCm: heightCm),
                 startDate: start)
            }
        }
        // モード中は目標の節目は出さない（もう届いているため）
        var milestoneNotifications = plannedMilestones(points: points, goal: maintenance == nil ? goal : nil, now: now, calendar: calendar)
        var result: [PlannedPraiseNotification] = []
        if let maintenance {
            result.append(contentsOf: plannedMaintenanceCrossings(
                points: points, range: maintenance.range, startDate: maintenance.startDate, now: now, calendar: calendar
            ))
        }

        if let recapFire = nextRecapDate(after: now, calendar: calendar) {
            let recordedDays = recordedDayCount(points: points, endingOn: recapFire, calendar: calendar)
            let keptInRange = maintenance.map {
                keptInRangeAllWeek(points: points, range: $0.range, startDate: $0.startDate, endingOn: recapFire, calendar: calendar)
            } ?? false
            // ふり返りと同じ時刻の節目のお祝いは、ふり返りにまとめる
            let sameTimeIndex = milestoneNotifications.firstIndex { $0.fireDate == recapFire }
            var mergedMilestone: PraiseMilestone?
            if let sameTimeIndex, case .milestone(let milestone) = milestoneNotifications[sameTimeIndex].kind {
                mergedMilestone = milestone
                milestoneNotifications.remove(at: sameTimeIndex)
            }
            if recordedDays > 0 {
                let text = recapMessage(recordedDays: recordedDays, milestone: mergedMilestone, keptInRange: keptInRange)
                result.append(PlannedPraiseNotification(
                    identifier: identifier(kind: "weeklyRecap", date: recapFire, calendar: calendar),
                    fireDate: recapFire,
                    kind: .weeklyRecap(recordedDays: recordedDays, milestone: mergedMilestone),
                    title: text.title,
                    body: text.body
                ))
            }
        }

        result.append(contentsOf: milestoneNotifications)
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - 週 1 回のふり返り

    /// `now` より後で、いちばん近い「日曜の夜 20:00」。
    static func nextRecapDate(after now: Date, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.weekday = recapWeekday
        components.hour = eveningTime.hour
        components.minute = eveningTime.minute
        components.second = 0
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }

    /// `endDate` の日を含めた直近 7 日間に、記録した日が何日あるか（同じ日の複数回は 1 日）。
    static func recordedDayCount(points: [WeightPoint], endingOn endDate: Date, calendar: Calendar) -> Int {
        let days = Set(points.map { calendar.startOfDay(for: $0.date) })
        return days.filter { day in
            let distance = DayMath.days(from: day, to: endDate, calendar: calendar)
            return distance >= 0 && distance < recapDays
        }.count
    }

    /// ふり返りの文面。記録した日数に応じて、いつもほめる言い方にします。
    /// - Parameter keptInRange: リバウンド抑制モード中で、この週の記録の日がすべて範囲の中だったか
    static func recapMessage(recordedDays: Int, milestone: PraiseMilestone?, keptInRange: Bool = false) -> (title: String, body: String) {
        let title = String(localized: "今週のふり返り")
        var sentences: [String] = []
        if let milestone {
            sentences.append(contentsOf: milestoneSentences(milestone))
        }
        if keptInRange {
            sentences.append(String(localized: "この1週間、範囲の中でキープできました！"))
        }
        if recordedDays >= recapDays {
            sentences.append(String(localized: "この1週間、毎日記録できました。すばらしい習慣です！"))
        } else if recordedDays >= 4 {
            sentences.append(String(localized: "この1週間で\(recordedDays)日記録できました。いいペースです！"))
        } else {
            sentences.append(String(localized: "この1週間で\(recordedDays)日記録できました。記録を続けていること自体が大きな一歩です。"))
        }
        return (title, sentences.joined())
    }

    // MARK: - リバウンド抑制モード

    /// 今日・昨日に範囲から出た・戻ったお知らせのうち、まだ出す時刻が来ていないもの。
    /// 前の記録の日と比べて切りかわった日だけなので、範囲の外にいるあいだに何度も届くことはありません。
    static func plannedMaintenanceCrossings(
        points: [WeightPoint],
        range: MaintenanceRange,
        startDate: Date,
        now: Date,
        calendar: Calendar
    ) -> [PlannedPraiseNotification] {
        let daily = WeightTrendCalculator.dailyAverages(points, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let candidateDays = [DayMath.date(byAddingDays: -1, to: today, calendar: calendar), today]

        var result: [PlannedPraiseNotification] = []
        for day in candidateDays {
            guard let crossing = MaintenanceAdvisor.crossing(on: day, daily: daily, range: range, startDate: startDate, calendar: calendar),
                  let fireDate = milestoneFireDate(on: day, points: points, calendar: calendar),
                  fireDate > now else { continue }
            let text = maintenanceMessage(crossing)
            result.append(PlannedPraiseNotification(
                identifier: identifier(kind: "maintenance", date: day, calendar: calendar),
                fireDate: fireDate,
                kind: .maintenance(crossing),
                title: text.title,
                body: text.body
            ))
        }
        return result
    }

    /// 範囲から出た・戻ったお知らせの文面。出たときも責めず、戻し方をそえます。
    static func maintenanceMessage(_ crossing: MaintenanceAdvisor.Crossing) -> (title: String, body: String) {
        switch crossing {
        case .left(.up):
            return (String(localized: "体重が範囲より少し上になりました"),
                    String(localized: "記録を続けているから早めに気づけました。あせらず、いつもの食事を少し整えれば戻せます。"))
        case .left(.down):
            return (String(localized: "体重が範囲より少し下になりました"),
                    String(localized: "記録を続けているから早めに気づけました。食事をしっかりとって、ゆっくり戻していきましょう。"))
        case .returned:
            return (String(localized: "範囲の中に戻りました！"),
                    String(localized: "ゆっくり整えてきた成果です。このままキープしていきましょう。"))
        }
    }

    /// `endDate` の日を含めた直近 7 日間（モードを始めた日より前は除く）に記録した日が 1 日以上あり、
    /// その日の目安がすべて範囲の中だったか。
    static func keptInRangeAllWeek(
        points: [WeightPoint],
        range: MaintenanceRange,
        startDate: Date,
        endingOn endDate: Date,
        calendar: Calendar
    ) -> Bool {
        let daily = WeightTrendCalculator.dailyAverages(points, calendar: calendar)
        let startDay = calendar.startOfDay(for: startDate)
        let weekDays = daily.map(\.date).filter { day in
            let distance = DayMath.days(from: day, to: endDate, calendar: calendar)
            return distance >= 0 && distance < recapDays && day >= startDay
        }
        guard !weekDays.isEmpty else { return false }
        return weekDays.allSatisfy { day in
            MaintenanceAdvisor.weightEstimate(asOf: day, daily: daily, calendar: calendar).map(range.contains) ?? false
        }
    }

    // MARK: - 節目のお祝い

    /// 今日・昨日に届いた節目のお祝いのうち、まだ出す時刻が来ていないもの。
    static func plannedMilestones(
        points: [WeightPoint],
        goal: DashboardGoal?,
        now: Date,
        calendar: Calendar
    ) -> [PlannedPraiseNotification] {
        let today = calendar.startOfDay(for: now)
        let candidateDays = [DayMath.date(byAddingDays: -1, to: today, calendar: calendar), today]

        var result: [PlannedPraiseNotification] = []
        for day in candidateDays {
            let milestone = PraiseMilestone(
                streakDays: streakMilestone(on: day, points: points, calendar: calendar),
                goalPercent: goal.flatMap { goalMilestone(on: day, points: points, goal: $0, calendar: calendar) }
            )
            guard milestone.streakDays != nil || milestone.goalPercent != nil,
                  let fireDate = milestoneFireDate(on: day, points: points, calendar: calendar),
                  fireDate > now else { continue }

            let text = milestoneMessage(milestone)
            result.append(PlannedPraiseNotification(
                identifier: identifier(kind: "milestone", date: day, calendar: calendar),
                fireDate: fireDate,
                kind: .milestone(milestone),
                title: text.title,
                body: text.body
            ))
        }
        return result
    }

    /// `day` の記録で、連続記録の節目（7 日連続など）に届いたか。届いていればその日数。
    static func streakMilestone(on day: Date, points: [WeightPoint], calendar: Calendar) -> Int? {
        let dates = points.map(\.date)
        let dayStart = calendar.startOfDay(for: day)
        // その日に記録がなければ、その日に節目に届いたことにはならない
        guard dates.contains(where: { calendar.startOfDay(for: $0) == dayStart }) else { return nil }
        let streak = WeighInStreakCalculator.currentStreak(dates: dates, today: dayStart, calendar: calendar)
        return PraiseMessageGenerator.streakMilestones.contains(streak) ? streak : nil
    }

    /// `day` の記録で、目標までの道のりの節目（25/50/75/100%）に初めて届いたか。届いていればいちばん大きい節目。
    static func goalMilestone(on day: Date, points: [WeightPoint], goal: DashboardGoal, calendar: Calendar) -> Int? {
        let daily = WeightTrendCalculator.dailyAverages(points, calendar: calendar)
        let dayStart = calendar.startOfDay(for: day)
        guard daily.contains(where: { $0.date == dayStart }),
              let startKg = goal.startWeightKg ?? daily.first?.weightKg else { return nil }

        /// `until` の日までの記録で見た、目標までの進み具合（%、切り捨て）
        func percent(until dayLimit: Date) -> Int? {
            let known = daily.filter { $0.date <= dayLimit }
            guard let currentKg = HomeDashboardBuilder.currentWeightEstimate(points: known, calendar: calendar),
                  let progress = HomeDashboardBuilder.goalProgress(startKg: startKg, currentKg: currentKg,
                                                                   targetKg: goal.targetWeightKg),
                  progress.isFinite else { return nil }
            return Int((progress * 100).rounded(.down))
        }

        guard let todayPercent = percent(until: dayStart) else { return nil }
        // それより前の日に一度でも届いていた節目は、もう一度お祝いしない
        let earlierBest = daily
            .filter { $0.date < dayStart }
            .compactMap { percent(until: $0.date) }
            .max() ?? 0
        return goalMilestonePercents.last { $0 <= todayPercent && $0 > earlierBest }
    }

    /// 節目のお祝いを出す日時。ふつうはその日の夜 20:00。
    /// その日の記録が 20:00 より後なら（夜に記録した人）、次の日の夜 20:00。
    static func milestoneFireDate(on day: Date, points: [WeightPoint], calendar: Calendar) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        guard let evening = calendar.date(bySettingHour: eveningTime.hour, minute: eveningTime.minute,
                                          second: 0, of: dayStart),
              let firstRecord = points.map(\.date).filter({ calendar.startOfDay(for: $0) == dayStart }).min()
        else { return nil }
        if firstRecord < evening { return evening }
        let nextDay = DayMath.date(byAddingDays: 1, to: dayStart, calendar: calendar)
        return calendar.date(bySettingHour: eveningTime.hour, minute: eveningTime.minute, second: 0, of: nextDay)
    }

    /// 節目のお祝いの文面。
    static func milestoneMessage(_ milestone: PraiseMilestone) -> (title: String, body: String) {
        let title = milestone.goalPercent == 100
            ? String(localized: "目標達成、おめでとうございます！")
            : String(localized: "節目に届きました！")
        let body = milestoneSentences(milestone).joined() + String(localized: "ここまで続けてきた自分をほめてあげてください。")
        return (title, body)
    }

    /// 節目ごとの一文（目標の節目を先に）。
    private static func milestoneSentences(_ milestone: PraiseMilestone) -> [String] {
        var sentences: [String] = []
        if let percent = milestone.goalPercent {
            sentences.append(percent >= 100
                ? String(localized: "目標の体重に届きました！")
                : String(localized: "目標までの道のりの\(percent)%に届きました！"))
        }
        if let days = milestone.streakDays {
            sentences.append(String(localized: "\(days)日連続で記録できました！"))
        }
        return sentences
    }

    /// 通知の ID（例: `praiseNotification.milestone.2026-11-21`）
    static func identifier(kind: String, date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let dateText = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return identifierPrefix + kind + "." + dateText
    }
}
