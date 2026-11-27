import Foundation

/// 妊娠中の体重の増え方が、目安の帯に対してどこにいるか
nonisolated enum PregnancyGainStatus: Equatable, Sendable {
    /// 妊娠が始まってからの記録がまだない
    case noRecords
    /// 一般的な目安を出さない（医師の目安を入れてもらう）
    case noGuide(PregnancyNoGuideReason)
    /// 目安の帯の中
    case withinRange
    /// 帯の下の端より少なめ（14 週から。初期はつわりで減る人も多いので言わない）
    case belowRange
    /// 帯の上の端より多め
    case aboveRange
}

/// 妊娠中モードのホームに出すもの。画面はこれを並べるだけにします。
nonisolated struct PregnancyDashboard: Equatable, Sendable {
    /// 今日の妊娠週数
    var age: GestationalAge
    /// 帯と判定に使う目安
    var target: PregnancyGainTarget
    /// 最新の体重（kg）。妊娠が始まってからの記録がなければ nil。
    var latestWeightKg: Double?
    /// 妊娠前からの増え方（最新の体重 − 妊娠前の体重、kg）。大きな数字に使う。
    var latestGainKg: Double?
    /// 判定に使った今の体重の目安（kg。直近 21 日の直線の今日の値、記録が 3 日未満なら最新の体重）
    var currentWeightKg: Double?
    /// 今日の帯（目安がないときは nil）
    var bandToday: PregnancyBandValue?
    /// 帯に対してどこにいるか
    var status: PregnancyGainStatus
    /// 直近 14 日（今日を含む）に記録した日数
    var recentRecordedDays: Int
    /// 「急に増えたときは、健診を待たずに相談すると安心です」をそえるか
    var showsRapidGainNote: Bool
    /// 出産予定日から 2 週間たったか（「妊娠中モードを続けますか？」のカードを出す）
    var isPastDueCheckIn: Bool
    /// グラフの帯（目安がないときは空）
    var bandPoints: [PregnancyBandPoint]
    /// 連続記録日数（ほめる言葉に使う）
    var streakDays: Int

    /// 「測れた日だけで大丈夫です」をそえるか（直近 14 日の記録が 3 日未満）
    var hasFewRecentRecords: Bool {
        recentRecordedDays < PregnancyAdvisor.fewRecordsThresholdDays
    }
}

/// 妊娠中モードの判断のルール（docs/PREGNANCY_MODE.md）。
///
/// - 大きな数字（妊娠前から +○ kg）は、ホームの「目標まで」と同じく最新の記録から出す。
/// - 帯の中か外かは、1 回の測定ではなく、ほかの画面と同じ **今の体重の目安**（直近 21 日の直線の今日の値）で判定する。
///   1 日だけ重い日に「多め」と言わないため。
/// - 「急な増え方」は、直線のペースが 1 週間で +1 kg 以上のとき（記録 7 日以上・14 日以上の期間があるときだけ）。数字はアプリの決まり。
///
/// SwiftUI / SwiftData には依存しない、ただの計算です。
nonisolated enum PregnancyAdvisor {
    /// 「急な増え方」とみなす 1 週間の増え方（kg）
    static let rapidGainKgPerWeek = 1.0
    /// 「急な増え方」を判定するのに必要な記録の日数
    static let rapidGainMinimumRecordedDays = 7
    /// 「急な増え方」を判定するのに必要な、最初と最後の記録の間の日数（2 週間「続いた」とみなすため）
    static let rapidGainMinimumSpanDays = 14
    /// 記録が少ないとみなす日数（直近 14 日でこれ未満）
    static let fewRecordsThresholdDays = 3
    /// 記録が少ないかを数える期間（日）
    static let recentWindowDays = 14
    /// 出産予定日から何日たったら「続けますか？」と聞くか
    static let checkInDaysAfterDue = 14
    /// 妊娠前の体重の候補に使う期間（妊娠 0 週の日より前の 30 日）
    static let prePregnancyLookbackDays = 30
    /// 小数の誤差で端ちょうどの体重が外になるのを防ぐ小さな値
    static let epsilon = 1e-9

    /// - Parameters:
    ///   - points: 体重の記録（順番はバラバラで OK）
    ///   - dueDate: 出産予定日
    ///   - prePregnancyWeightKg: 妊娠前の体重（kg）
    ///   - heightCm: 身長（cm）
    ///   - isMultiple: 赤ちゃんが 2 人以上か
    ///   - customLowKg / customHighKg: 健診で言われた目安（入れていなければ nil）
    static func evaluate(
        points: [WeightPoint],
        dueDate: Date,
        prePregnancyWeightKg: Double,
        heightCm: Double,
        isMultiple: Bool,
        customLowKg: Double?,
        customHighKg: Double?,
        now: Date,
        calendar: Calendar = .current
    ) -> PregnancyDashboard {
        let age = GestationalAgeCalculator.age(dueDate: dueDate, on: now, calendar: calendar)
        let target = PregnancyWeightGainGuide.target(
            prePregnancyWeightKg: prePregnancyWeightKg,
            heightCm: heightCm,
            isMultiple: isMultiple,
            customLowKg: customLowKg,
            customHighKg: customHighKg
        )

        // 妊娠 0 週の日から今日までの記録だけを使う（妊娠前の記録で判定がずれないように）
        let start = GestationalAgeCalculator.startDate(dueDate: dueDate, calendar: calendar)
        let endOfToday = DayMath.date(byAddingDays: 1, to: now, calendar: calendar)
        let pregnancyPoints = points.filter { $0.date >= start && $0.date < endOfToday }
        let latest = pregnancyPoints.max { $0.date < $1.date }
        let estimate = GoalForecaster.paceEstimate(points: pregnancyPoints, calendar: calendar)
        let currentWeightKg = estimate?.currentWeightKg ?? latest?.weightKg

        let bandToday = target.range.map { PregnancyBandBuilder.band(atDay: age.totalDays, range: $0) }
        let status = gainStatus(
            target: target,
            currentWeightKg: currentWeightKg,
            prePregnancyWeightKg: prePregnancyWeightKg,
            bandToday: bandToday,
            age: age
        )

        let showsRapidGainNote: Bool = {
            guard let estimate,
                  estimate.recordedDays >= rapidGainMinimumRecordedDays,
                  DayMath.days(from: estimate.firstDate, to: estimate.latestDate, calendar: calendar) >= rapidGainMinimumSpanDays
            else { return false }
            return estimate.weeklyChangeKg >= rapidGainKgPerWeek - epsilon
        }()

        let bandPoints = target.range.map {
            PregnancyBandBuilder.chartPoints(dueDate: dueDate, prePregnancyWeightKg: prePregnancyWeightKg, range: $0, calendar: calendar)
        } ?? []

        return PregnancyDashboard(
            age: age,
            target: target,
            latestWeightKg: latest?.weightKg,
            latestGainKg: latest.map { $0.weightKg - prePregnancyWeightKg },
            currentWeightKg: currentWeightKg,
            bandToday: bandToday,
            status: status,
            recentRecordedDays: recentRecordedDays(points: points, now: now, calendar: calendar),
            showsRapidGainNote: showsRapidGainNote,
            isPastDueCheckIn: DayMath.days(from: dueDate, to: now, calendar: calendar) >= checkInDaysAfterDue,
            bandPoints: bandPoints,
            streakDays: WeighInStreakCalculator.currentStreak(dates: points.map(\.date), today: now, calendar: calendar)
        )
    }

    /// 帯に対してどこにいるか
    static func gainStatus(
        target: PregnancyGainTarget,
        currentWeightKg: Double?,
        prePregnancyWeightKg: Double,
        bandToday: PregnancyBandValue?,
        age: GestationalAge
    ) -> PregnancyGainStatus {
        guard let currentWeightKg else { return .noRecords }
        if case .needsDoctor(let reason) = target { return .noGuide(reason) }
        guard let bandToday else { return .withinRange }
        let gain = currentWeightKg - prePregnancyWeightKg
        if gain > bandToday.upperGainKg + epsilon {
            return .aboveRange
        }
        // 初期（13 週まで）は、つわりで減る人も多いので「少なめ」とは言わない
        if age.trimester != .early, gain < bandToday.lowerGainKg - epsilon {
            return .belowRange
        }
        return .withinRange
    }

    /// 直近 14 日（今日を含む）に記録した日数。未来の日付は数えない。
    static func recentRecordedDays(points: [WeightPoint], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(points.map { calendar.startOfDay(for: $0.date) })
        return days.filter { day in
            let distance = DayMath.days(from: day, to: now, calendar: calendar)
            return distance >= 0 && distance < recentWindowDays
        }.count
    }

    /// 妊娠前の体重の候補：妊娠 0 週の日（予定日の 280 日前）より前の 30 日の記録の平均（0.1 kg 単位）。なければ nil。
    ///
    /// 同じ日の記録は平均して 1 日 1 つにしてから平均します（1 日にたくさん測った日だけが重くならないように）。
    static func prePregnancyWeightSuggestion(points: [WeightPoint], dueDate: Date, calendar: Calendar = .current) -> Double? {
        let start = GestationalAgeCalculator.startDate(dueDate: dueDate, calendar: calendar)
        let from = DayMath.date(byAddingDays: -prePregnancyLookbackDays, to: start, calendar: calendar)
        let window = points.filter { $0.date >= from && $0.date < start }
        let daily = WeightTrendCalculator.dailyAverages(window, calendar: calendar)
        guard !daily.isEmpty else { return nil }
        let average = daily.map(\.weightKg).reduce(0, +) / Double(daily.count)
        return (average * 10).rounded() / 10
    }
}
