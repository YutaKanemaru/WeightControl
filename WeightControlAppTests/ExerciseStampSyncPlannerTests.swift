import Foundation
import Testing
@testable import WeightControlApp

/// ヘルスケアの運動量から運動スタンプを押すルール（DailyActivity・ExerciseDayDetector・ExerciseStampSyncPlanner）のテスト
struct ExerciseStampSyncPlannerTests {
    private let calendar = TestCalendar.utc

    private func activity(_ day: Int, exercise: Double = 0, workout: Double = 0, steps: Double = 0) -> DailyActivity {
        DailyActivity(day: TestCalendar.day(day), exerciseMinutes: exercise, workoutMinutes: workout, steps: steps)
    }

    // MARK: - DailyActivity.days

    @Test("期間の毎日を作り、データがない日は 0 にする。同じ日の値は足し合わせる")
    func buildsEveryDay() {
        let days = DailyActivity.days(
            from: TestCalendar.day(0, hour: 15),
            through: TestCalendar.day(2, hour: 9),
            exerciseMinutes: [TestCalendar.day(0, hour: 8): 10, TestCalendar.day(0, hour: 18): 15],
            steps: [TestCalendar.day(2): 3_000],
            calendar: calendar
        )
        #expect(days.map(\.day) == [TestCalendar.day(0), TestCalendar.day(1), TestCalendar.day(2)])
        #expect(days[0].exerciseMinutes == 25)
        #expect(days[1].hasAnyData == false)
        #expect(days[2].steps == 3_000)
    }

    // MARK: - ExerciseDayDetector

    @Test("運動時間 20 分以上か、1 万歩以上なら運動した日")
    func detectsExerciseDay() {
        #expect(ExerciseDayDetector.isExerciseDay(activity(0, exercise: 20)))
        #expect(ExerciseDayDetector.isExerciseDay(activity(0, workout: 45)))
        #expect(ExerciseDayDetector.isExerciseDay(activity(0, steps: 10_000)))
        #expect(!ExerciseDayDetector.isExerciseDay(activity(0, exercise: 19, steps: 9_999)))
    }

    @Test("運動時間は、エクササイズとワークアウトの大きい方（二重に数えない）")
    func activeMinutesUsesLarger() {
        #expect(activity(0, exercise: 30, workout: 25).activeMinutes == 30)
        #expect(activity(0, exercise: 10, workout: 40.4).activeMinutes == 40)
    }

    // MARK: - ExerciseStampSyncPlanner

    @Test("運動した日にスタンプがなければ、自動のスタンプを押す")
    func addsStamp() {
        let changes = ExerciseStampSyncPlanner.changes(
            activities: [activity(1, exercise: 30), activity(2, exercise: 5)], existing: [], calendar: calendar
        )
        #expect(changes == [.add(day: TestCalendar.day(1), activeMinutes: 30)])
    }

    @Test("自分で押したスタンプがある日は、何も変えない")
    func keepsManualStamp() {
        let changes = ExerciseStampSyncPlanner.changes(
            activities: [activity(1, exercise: 30)],
            existing: [ExistingExerciseStamp(day: TestCalendar.day(1), isFromHealthKit: false, activeMinutes: nil)],
            calendar: calendar
        )
        #expect(changes.isEmpty)
    }

    @Test("自動のスタンプは、運動時間が変われば書き換え、同じなら何もしない")
    func updatesMinutes() {
        let existing = [
            ExistingExerciseStamp(day: TestCalendar.day(1), isFromHealthKit: true, activeMinutes: 25),
            ExistingExerciseStamp(day: TestCalendar.day(2), isFromHealthKit: true, activeMinutes: 40),
        ]
        let changes = ExerciseStampSyncPlanner.changes(
            activities: [activity(1, exercise: 35), activity(2, exercise: 40)], existing: existing, calendar: calendar
        )
        #expect(changes == [.updateMinutes(day: TestCalendar.day(1), activeMinutes: 35)])
    }

    @Test("運動の記録がなくなった日の自動スタンプは外す。手動のスタンプと対象外の日はそのまま")
    func removesStaleAutomaticStamp() {
        let existing = [
            ExistingExerciseStamp(day: TestCalendar.day(1), isFromHealthKit: true, activeMinutes: 25),
            ExistingExerciseStamp(day: TestCalendar.day(2), isFromHealthKit: false, activeMinutes: nil),
            ExistingExerciseStamp(day: TestCalendar.day(-30), isFromHealthKit: true, activeMinutes: 25),
        ]
        let changes = ExerciseStampSyncPlanner.changes(
            activities: [activity(1), activity(2)], existing: existing, calendar: calendar
        )
        #expect(changes == [.remove(day: TestCalendar.day(1))])
    }
}
