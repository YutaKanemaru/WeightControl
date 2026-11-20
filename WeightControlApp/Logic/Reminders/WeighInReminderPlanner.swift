import Foundation

/// リマインド通知を出す時刻（時・分）。
nonisolated struct ReminderTime: Equatable, Sendable {
    /// 時（0〜23）
    var hour: Int
    /// 分（0〜59）
    var minute: Int

    /// 既定は朝 7:00。体重は「朝、トイレのあと・朝食の前」に測ると日々のブレが小さくなるためです。
    static let defaultTime = ReminderTime(hour: 7, minute: 0)

    /// 範囲外の値（25 時など）が保存されていても壊れないように、0〜23 時・0〜59 分に収めます。
    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }
}

/// 登録する予定の通知 1 件分。通知の仕組み（UserNotifications）には依存しない、ただの値です。
nonisolated struct PlannedReminder: Equatable, Sendable {
    /// 通知の文面の種類。テストや、将来アイコンを変えたいときに使います。
    enum Kind: Equatable, Sendable {
        /// まだ 1 回も記録していない
        case firstRecord
        /// 連続記録が途切れている。再開をやさしく促す
        case restart
        /// 連続記録中。`days` はその日の前日までの連続日数
        case continueStreak(days: Int)
        /// 今日記録すると節目（7 日連続など）になる。`nextDays` は記録したあとの連続日数
        case upcomingMilestone(nextDays: Int)
    }

    /// 通知の ID。日付ごとに 1 つ（例: `weighInReminder.2026-11-21`）。
    var identifier: String
    /// 通知を出す日時
    var fireDate: Date
    var kind: Kind
    var title: String
    var body: String
}

/// 「体重を記録しましょう」のリマインド通知を、いつ・どんな文面で出すかを決めるロジック。
///
/// ## なぜ毎日くり返す通知ではなく、1 日ずつ登録するのか
/// iOS には「毎日 7:00 にくり返す」通知もありますが、通知が出る瞬間にアプリのコードは動かないので、
/// 「今日はもう記録したから出さない」「連続記録の日数を入れる」といった判断ができません。
/// そこで、アプリを開いたときや記録したときに、この先 `daysAhead` 日分の通知を 1 日ずつ作り直します。
///
/// ルール:
/// - すでに記録した日には通知しない（記録したのに「記録しましょう」と言われるとがっかりするため）
/// - 時刻が過ぎている今日の分は作らない
/// - 文面は「ほめる」を優先し、途切れていても責めない
/// - アプリをしばらく開かないと、`daysAhead` 日で通知は自然に止まる（しつこくしないため）
nonisolated enum WeighInReminderPlanner {
    /// このアプリのリマインド通知であることを示す ID の先頭部分
    static let identifierPrefix = "weighInReminder."
    /// 何日先までの通知を登録しておくか
    static let defaultDaysAhead = 7

    /// これから登録する通知の一覧を、日付の早い順に返します。
    ///
    /// - Parameters:
    ///   - time: 通知を出す時刻
    ///   - recordedDates: 体重を記録した日時の一覧（順番はバラバラで OK）
    ///   - now: 「今」とみなす日時。テストで日付を固定できるように引数にしています。
    ///   - calendar: 日付の区切り（タイムゾーン）を決めるカレンダー
    ///   - daysAhead: 今日を含めて何日分を作るか
    static func plan(
        time: ReminderTime,
        recordedDates: [Date],
        now: Date = .now,
        calendar: Calendar = .current,
        daysAhead: Int = defaultDaysAhead
    ) -> [PlannedReminder] {
        guard daysAhead > 0 else { return [] }
        let recordedDays = Set(recordedDates.map { calendar.startOfDay(for: $0) })

        var result: [PlannedReminder] = []
        for offset in 0..<daysAhead {
            let dayStart = DayMath.date(byAddingDays: offset, to: now, calendar: calendar)
            // その日にもう記録があれば通知しない
            if recordedDays.contains(dayStart) { continue }
            guard let fireDate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: dayStart),
                  fireDate > now else { continue }

            // 通知が出る日の時点での連続記録日数（その日はまだ記録していないので、前日までの日数になる）
            let streakSoFar = WeighInStreakCalculator.currentStreak(dates: recordedDates, today: fireDate, calendar: calendar)
            let hasEarlierRecord = recordedDays.contains { $0 < dayStart }
            let message = message(streakSoFar: streakSoFar, hasEarlierRecord: hasEarlierRecord)

            result.append(PlannedReminder(
                identifier: identifier(for: dayStart, calendar: calendar),
                fireDate: fireDate,
                kind: message.kind,
                title: message.title,
                body: message.body
            ))
        }
        return result
    }

    /// 通知の文面を決めます。
    ///
    /// - Parameters:
    ///   - streakSoFar: 通知を出す日の前日までの連続記録日数
    ///   - hasEarlierRecord: それより前に 1 回でも記録したことがあるか
    static func message(streakSoFar: Int, hasEarlierRecord: Bool) -> (kind: PlannedReminder.Kind, title: String, body: String) {
        let title = String(localized: "今日の体重を記録しましょう")

        if streakSoFar >= 1 {
            let nextDays = streakSoFar + 1
            if PraiseMessageGenerator.streakMilestones.contains(nextDays) {
                return (.upcomingMilestone(nextDays: nextDays), title,
                        String(localized: "今日記録すると\(nextDays)日連続の節目です！体重計に乗って、数字を入れるだけで OK です。"))
            }
            return (.continueStreak(days: streakSoFar), title,
                    String(localized: "\(streakSoFar)日連続で記録できています。今日も記録して、\(nextDays)日目につなげましょう。"))
        }

        if hasEarlierRecord {
            return (.restart, title,
                    String(localized: "記録はいつからでも再開できます。体重計に乗って、数字を入れるだけで OK です。"))
        }
        return (.firstRecord, title,
                String(localized: "体重計に乗って、最初の記録をつけてみましょう。数字を入れるだけで OK です。"))
    }

    /// 日付ごとの通知 ID（例: `weighInReminder.2026-11-21`）。同じ日の通知を作り直すと、上書きされます。
    static func identifier(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let dateText = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return identifierPrefix + dateText
    }
}
