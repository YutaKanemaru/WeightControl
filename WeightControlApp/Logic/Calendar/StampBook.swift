import Foundation

/// カレンダーのスタンプ帳：どの日に「体重を測った」「運動した」スタンプと、チートデー（Pro）の印があるかをまとめたもの。
///
/// チートデーは「がんばった記録」ではなく予定なので、今月のスタンプの数や連続記録には数えません。
///
/// 記録の日時を「その日の 0 時」にそろえて集合（Set）にしておくので、
/// 同じ日に何回記録しても 1 つのスタンプとして数えます。
nonisolated struct StampBook: Sendable {
    /// 体重を測った日（0 時にそろえたもの）
    let weighInDays: Set<Date>
    /// 運動した日（0 時にそろえたもの）
    let exerciseDays: Set<Date>
    /// チートデーにした日（0 時にそろえたもの。未来の日もある）
    let cheatDays: Set<Date>
    private let calendar: Calendar

    /// - Parameters:
    ///   - weighInDates: 体重を記録した日時の一覧（順番はバラバラで OK）
    ///   - exerciseDates: 運動した日の一覧
    ///   - cheatDayDates: チートデーにした日の一覧（Pro。使わないときは空）
    ///   - calendar: 日付の区切り（タイムゾーン）を決めるカレンダー
    init(weighInDates: [Date], exerciseDates: [Date], cheatDayDates: [Date] = [], calendar: Calendar = .current) {
        self.weighInDays = Set(weighInDates.map { calendar.startOfDay(for: $0) })
        self.exerciseDays = Set(exerciseDates.map { calendar.startOfDay(for: $0) })
        self.cheatDays = Set(cheatDayDates.map { calendar.startOfDay(for: $0) })
        self.calendar = calendar
    }

    /// その日に体重を測ったか
    func hasWeighIn(on date: Date) -> Bool {
        weighInDays.contains(calendar.startOfDay(for: date))
    }

    /// その日に運動したか
    func hasExercise(on date: Date) -> Bool {
        exerciseDays.contains(calendar.startOfDay(for: date))
    }

    /// その日がチートデーか
    func hasCheatDay(on date: Date) -> Bool {
        cheatDays.contains(calendar.startOfDay(for: date))
    }

    /// `date` を含む月のチートデーの日数
    func cheatDayCount(inMonthContaining date: Date) -> Int {
        cheatDays.filter { isSameMonth($0, date) }.count
    }

    /// `date` を含む月に押されたスタンプの数（体重と運動の合計。同じ日に両方あれば 2 個）
    func stampCount(inMonthContaining date: Date) -> Int {
        weighInCount(inMonthContaining: date) + exerciseCount(inMonthContaining: date)
    }

    /// `date` を含む月に体重を測った日数
    func weighInCount(inMonthContaining date: Date) -> Int {
        weighInDays.filter { isSameMonth($0, date) }.count
    }

    /// `date` を含む月に運動した日数
    func exerciseCount(inMonthContaining date: Date) -> Int {
        exerciseDays.filter { isSameMonth($0, date) }.count
    }

    /// 体重を何日連続で測れているか（今日まだでも、昨日まで続いていれば途切れていない扱い）
    func weighInStreak(today: Date = .now) -> Int {
        WeighInStreakCalculator.currentStreak(dates: Array(weighInDays), today: today, calendar: calendar)
    }

    /// 体重か運動、どちらかのスタンプが何日連続で押せているか
    func anyStampStreak(today: Date = .now) -> Int {
        WeighInStreakCalculator.currentStreak(
            dates: Array(weighInDays.union(exerciseDays)), today: today, calendar: calendar
        )
    }

    private func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }
}

/// 日付をタップしたときに、運動スタンプをどうするかを決めるルール。
nonisolated enum ExerciseStampRule {
    /// タップしたときの動き
    nonisolated enum Action: Equatable, Sendable {
        /// 手動のスタンプを押す
        case add
        /// 手動のスタンプを取り消す
        case remove
        /// 何もしない（未来の日、または HealthKit から取り込んだスタンプだけがある日）
        case none
    }

    /// - Parameters:
    ///   - day: タップした日
    ///   - today: 「今日」とみなす日時
    ///   - hasManualStamp: その日に自分で押したスタンプがあるか
    ///   - hasAutomaticStamp: その日に HealthKit から取り込んだスタンプがあるか
    ///     （ヘルスケアの記録が元なので、アプリの中では消さないようにする）
    static func action(
        forTapOn day: Date,
        today: Date = .now,
        hasManualStamp: Bool,
        hasAutomaticStamp: Bool,
        calendar: Calendar = .current
    ) -> Action {
        // まだ来ていない日には押せない
        if calendar.startOfDay(for: day) > calendar.startOfDay(for: today) {
            return .none
        }
        if hasManualStamp {
            return .remove
        }
        if hasAutomaticStamp {
            return .none
        }
        return .add
    }
}
