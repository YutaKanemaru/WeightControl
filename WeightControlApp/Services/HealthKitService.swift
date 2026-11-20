import Foundation
import HealthKit

/// Apple の「ヘルスケア」（HealthKit）とやり取りする窓口。
///
/// HealthKit の型（`HKQuantitySample` など）はこのファイルの中だけで扱い、
/// 外には `HealthWeightSample` や `DailyActivity` のような「値の型」に変換して渡します。
/// こうしておくと、重複チェックなどのルール（`Logic/Health/`）を HealthKit なしでテストできます。
///
/// 使うデータの種類：
/// - 読み取り：体重、エクササイズ時間、アクティブエネルギー、歩数、ワークアウト
/// - 書き込み：体重（設定でオンにしたときだけ）
final class HealthKitService {
    /// ヘルスケアのデータベースへの接続。アプリで 1 つあれば十分です。
    private let store = HKHealthStore()

    private let bodyMassType = HKQuantityType(.bodyMass)
    private let kilogram = HKUnit.gramUnit(with: .kilo)

    /// この端末でヘルスケアが使えるか（iPhone は使える。一部の iPad などは使えない）
    static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - 許可

    /// ヘルスケアへのアクセス許可を求めます。初回は、どのデータを許可するか選ぶ画面が出ます。
    ///
    /// 注意：プライバシー保護のため、HealthKit は「読み取りを許可されたかどうか」をアプリに教えてくれません。
    /// 読み取りを許可されていない場合は、エラーではなく「データが 0 件」として返ってきます。
    func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [
            bodyMassType,
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKObjectType.workoutType(),
        ]
        try await store.requestAuthorization(toShare: [bodyMassType], read: readTypes)
    }

    /// 体重の書き込みが許可されているか（書き込みの方は、許可の状態を確かめられます）
    var canWriteWeight: Bool {
        store.authorizationStatus(for: bodyMassType) == .sharingAuthorized
    }

    // MARK: - 体重の読み取り

    /// 前回の同期から後に、ヘルスケアで追加・削除された体重の記録。
    struct WeightChanges {
        let added: [HealthWeightSample]
        let deletedIDs: Set<UUID>
        /// 次回の同期に使う「しおり」。保存しておき、次回 `fetchWeightChanges` に渡します。
        let newAnchorData: Data?
    }

    /// 前回の同期から後の、体重の追加・削除を読み取ります。
    ///
    /// 「アンカー（しおり）」付きの問い合わせ（`HKAnchoredObjectQuery`）を使うので、
    /// 前回どこまで読んだかを覚えておけば、それより後の変化だけが届きます。
    /// アンカーが nil（初回）のときは、ヘルスケアにある体重の記録がすべて届きます。
    func fetchWeightChanges(anchorData: Data?) async throws -> WeightChanges {
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: bodyMassType)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)

        let thisAppBundleID = Bundle.main.bundleIdentifier
        let added = result.addedSamples.map { sample in
            HealthWeightSample(
                id: sample.uuid,
                date: sample.startDate,
                weightKg: sample.quantity.doubleValue(for: kilogram),
                isFromThisApp: sample.sourceRevision.source.bundleIdentifier == thisAppBundleID
            )
        }
        let newAnchorData = try? NSKeyedArchiver.archivedData(
            withRootObject: result.newAnchor, requiringSecureCoding: true
        )
        return WeightChanges(
            added: added,
            deletedIDs: Set(result.deletedObjects.map(\.uuid)),
            newAnchorData: newAnchorData
        )
    }

    // MARK: - 体重の書き込み・削除

    /// 体重をヘルスケアに書き込み、書き込んだ記録の ID を返します。
    func saveWeight(weightKg: Double, date: Date) async throws -> UUID {
        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: HKQuantity(unit: kilogram, doubleValue: weightKg),
            start: date,
            end: date
        )
        try await store.save(sample)
        return sample.uuid
    }

    /// このアプリが書き込んだ体重の記録を、ヘルスケアから削除します。
    /// （ほかのアプリが書いた記録は、HealthKit のルールで削除できません）
    /// 結果は待たずに、裏で削除を進めます（失敗しても、アプリ側の記録の削除には影響しません）。
    func deleteWeight(id: UUID) {
        store.deleteObjects(of: bodyMassType, predicate: HKQuery.predicateForObject(with: id)) { _, _, _ in }
    }

    // MARK: - 運動量の読み取り

    /// `start` の日から `end` の日までの、1 日ごとの運動量を読み取ります。
    ///
    /// 読み取りを許可されていない種類のデータは 0 として扱います（1 つ失敗しても、ほかは読めるようにする）。
    func fetchDailyActivity(from start: Date, through end: Date, calendar: Calendar) async -> [DailyActivity] {
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = DayMath.date(byAddingDays: 1, to: end, calendar: calendar)

        let exercise = (try? await dailySums(.appleExerciseTime, unit: .minute(), from: rangeStart, to: rangeEnd)) ?? [:]
        let energy = (try? await dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: rangeStart, to: rangeEnd)) ?? [:]
        let steps = (try? await dailySums(.stepCount, unit: .count(), from: rangeStart, to: rangeEnd)) ?? [:]
        let workouts = (try? await dailyWorkoutMinutes(from: rangeStart, to: rangeEnd)) ?? [:]

        return DailyActivity.days(
            from: rangeStart,
            through: end,
            exerciseMinutes: exercise,
            workoutMinutes: workouts,
            activeEnergyKcal: energy,
            steps: steps,
            calendar: calendar
        )
    }

    /// 1 日ごとの合計（歩数・カロリーなど）。HealthKit の「統計の問い合わせ」で、日ごとに足し合わせてもらいます。
    private func dailySums(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async throws -> [Date: Double] {
        let type = HKQuantityType(identifier)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)

        var sums: [Date: Double] = [:]
        for statistics in collection.statistics() {
            if let sum = statistics.sumQuantity() {
                sums[statistics.startDate] = sum.doubleValue(for: unit)
            }
        }
        return sums
    }

    /// 1 日ごとのワークアウトの合計時間（分）。ワークアウトを始めた日に数えます。
    private func dailyWorkoutMinutes(from start: Date, to end: Date) async throws -> [Date: Double] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: []
        )
        let workouts = try await descriptor.result(for: store)

        var minutes: [Date: Double] = [:]
        for workout in workouts {
            minutes[workout.startDate, default: 0] += workout.duration / 60
        }
        return minutes
    }
}
