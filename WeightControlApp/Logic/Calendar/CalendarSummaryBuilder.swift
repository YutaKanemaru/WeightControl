import Foundation

/// カレンダータブの上のカードに出す「まとめ」の数字。画面や保存の仕組みには依存しない、ただの値です。
nonisolated struct CalendarSummary: Equatable, Sendable {
    /// 連続記録日数に合わせた、ひとことの種類。文面は画面側（String Catalog）で決めます。
    enum Encouragement: Equatable, Sendable {
        /// スタンプがまだ 1 つもない（はじめて使う人）
        case firstStamp
        /// 以前は記録していたが、今は途切れている。責めずに再開を応援する
        case restart
        /// 1〜2 日。いいスタート
        case goodStart(days: Int)
        /// 3〜6 日。習慣になってきた
        case buildingHabit(days: Int)
        /// 7 日以上。すばらしい習慣
        case habit(days: Int)
    }

    /// 体重を何日連続で測れているか（`StampBook.weighInStreak` と同じ数え方）
    let streakDays: Int
    /// 今月、体重を測った日数
    let monthWeighInDays: Int
    /// 今月、運動した日数
    let monthExerciseDays: Int
    /// 今日、体重を測ったか
    let hasWeighInToday: Bool
    /// 今日、運動スタンプがあるか
    let hasExerciseToday: Bool
    /// 体重・運動どちらかのスタンプが、これまでに 1 つでもあるか（空の状態の判断に使う）
    let hasAnyStamp: Bool
    /// 画面に出すひとことの種類
    let encouragement: Encouragement

    /// 今月のスタンプの数（体重と運動の合計。同じ日に両方あれば 2 個）
    var monthStampCount: Int { monthWeighInDays + monthExerciseDays }
}

/// スタンプ帳（`StampBook`）から、カレンダータブの「まとめ」を作るロジック。
///
/// 数え方そのものは `StampBook` にあり、ここでは画面に出す形にまとめるだけです。
nonisolated enum CalendarSummaryBuilder {
    /// 「習慣になってきた」とみなす連続日数
    static let buildingHabitDays = 3
    /// 「すばらしい習慣」とみなす連続日数
    static let habitDays = 7

    /// - Parameters:
    ///   - stampBook: 体重・運動のスタンプ帳
    ///   - today: 「今日」とみなす日時。この日を含む月を「今月」として数えます。
    static func build(stampBook: StampBook, today: Date = .now) -> CalendarSummary {
        let streak = stampBook.weighInStreak(today: today)
        let hasAnyStamp = !stampBook.weighInDays.isEmpty || !stampBook.exerciseDays.isEmpty
        return CalendarSummary(
            streakDays: streak,
            monthWeighInDays: stampBook.weighInCount(inMonthContaining: today),
            monthExerciseDays: stampBook.exerciseCount(inMonthContaining: today),
            hasWeighInToday: stampBook.hasWeighIn(on: today),
            hasExerciseToday: stampBook.hasExercise(on: today),
            hasAnyStamp: hasAnyStamp,
            encouragement: encouragement(streakDays: streak, hasAnyStamp: hasAnyStamp)
        )
    }

    /// 連続記録日数から、ひとことの種類を選ぶ
    static func encouragement(streakDays: Int, hasAnyStamp: Bool) -> CalendarSummary.Encouragement {
        if streakDays < 1 {
            return hasAnyStamp ? .restart : .firstStamp
        } else if streakDays < buildingHabitDays {
            return .goodStart(days: streakDays)
        } else if streakDays < habitDays {
            return .buildingHabit(days: streakDays)
        } else {
            return .habit(days: streakDays)
        }
    }
}
