import Foundation

/// ヘルスケアから読んだ「1 日分の運動量」。
nonisolated struct DailyActivity: Equatable, Sendable {
    /// その日の 0 時
    let day: Date
    /// Apple の「エクササイズ」の時間（分）。Apple Watch などが、早歩き以上の動きを自動で数えたもの。
    var exerciseMinutes: Double = 0
    /// ワークアウト（運動の記録）の合計時間（分）。ほかの運動アプリの記録も含みます。
    var workoutMinutes: Double = 0
    /// アクティブエネルギー（動いたことで使ったカロリー、kcal）
    var activeEnergyKcal: Double = 0
    /// 歩数
    var steps: Double = 0

    /// 何かしらデータがある日か（スマホを置きっぱなしだった日などを平均から外すため）
    var hasAnyData: Bool {
        exerciseMinutes > 0 || workoutMinutes > 0 || activeEnergyKcal > 0 || steps > 0
    }

    /// 運動した時間（分）。エクササイズとワークアウトは同じ運動を二重に数えていることが多いので、大きい方を使います。
    var activeMinutes: Int {
        Int(max(exerciseMinutes, workoutMinutes).rounded())
    }

    /// 日ごとの合計値（キーは日時）から、`start` 〜 `end` の毎日の `DailyActivity` を作ります。
    ///
    /// データがない日も「0 の日」として入れます（スタンプを外す判定に使うため）。
    /// キーの日時は 0 時でなくても、その日にまとめて足し合わせます。
    static func days(
        from start: Date,
        through end: Date,
        exerciseMinutes: [Date: Double] = [:],
        workoutMinutes: [Date: Double] = [:],
        activeEnergyKcal: [Date: Double] = [:],
        steps: [Date: Double] = [:],
        calendar: Calendar
    ) -> [DailyActivity] {
        func byDay(_ values: [Date: Double]) -> [Date: Double] {
            values.reduce(into: [:]) { result, pair in
                result[calendar.startOfDay(for: pair.key), default: 0] += pair.value
            }
        }
        let exercise = byDay(exerciseMinutes)
        let workouts = byDay(workoutMinutes)
        let energy = byDay(activeEnergyKcal)
        let stepCounts = byDay(steps)

        let dayCount = DayMath.days(from: start, to: end, calendar: calendar)
        guard dayCount >= 0 else { return [] }
        return (0...dayCount).map { offset in
            let day = DayMath.date(byAddingDays: offset, to: start, calendar: calendar)
            return DailyActivity(
                day: day,
                exerciseMinutes: exercise[day] ?? 0,
                workoutMinutes: workouts[day] ?? 0,
                activeEnergyKcal: energy[day] ?? 0,
                steps: stepCounts[day] ?? 0
            )
        }
    }
}
