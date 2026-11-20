import Foundation
import Observation
import SwiftData

/// ヘルスケアとアプリの記録を同期する係。
///
/// - 「連携する」をオンにしたとき、アプリが前面に来たとき、「今すぐ同期」を押したときに `sync` が呼ばれます。
/// - 体重：ヘルスケアの新しい記録を `WeightEntry` として取り込みます（重複は `HealthWeightImportPlanner` で除外）。
/// - 運動：直近の運動量から、カレンダーの運動スタンプ（`ExerciseDay`）を自動で押します。
/// - アプリで入力した体重は、設定でオンにしていればヘルスケアにも書き込みます。
///
/// `@Observable` を付けると、このクラスの値（同期中かどうか など）が変わったときに、画面が自動で描き直されます。
/// 設定（オン・オフ）は端末内の `UserDefaults` に保存します（外部には送りません）。
@Observable
final class HealthSyncController {
    /// 同期の状態（画面に表示する）
    enum Status: Equatable {
        case idle
        case syncing
        case finished(at: Date, importedWeightCount: Int)
        case failed(message: String)
    }

    /// 運動スタンプを見直す日数（今日を含めて過去何日分か）
    static let exerciseLookbackDays = 60
    /// 活動量の目安に使う日数
    static let activitySummaryDays = 28

    private(set) var status: Status = .idle
    /// ヘルスケアの実績から見た運動量のまとめ（データが少ないときは nil）
    private(set) var activitySummary: ActivitySummary?

    /// ヘルスケアと連携するか
    private(set) var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// アプリで入力した体重を、ヘルスケアにも書き込むか
    var writesWeightToHealth: Bool {
        didSet { defaults.set(writesWeightToHealth, forKey: Keys.writesWeight) }
    }

    @ObservationIgnored private let service = HealthKitService()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar = Calendar.current

    private enum Keys {
        static let isEnabled = "health.isEnabled"
        static let writesWeight = "health.writesWeightToHealth"
        static let weightAnchor = "health.weightAnchor"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.writesWeightToHealth = defaults.object(forKey: Keys.writesWeight) as? Bool ?? true
    }

    /// この端末でヘルスケアが使えるか
    var isAvailable: Bool { HealthKitService.isHealthDataAvailable }

    var isSyncing: Bool { status == .syncing }

    // MARK: - オン・オフ

    /// 連携をオンにします。許可を求める画面を出し、そのまま 1 回同期します。
    func enable(context: ModelContext) async {
        guard isAvailable else { return }
        do {
            try await service.requestAuthorization()
            isEnabled = true
            await sync(context: context)
        } catch {
            status = .failed(message: String(localized: "ヘルスケアへのアクセスを始められませんでした。"))
        }
    }

    /// 連携をオフにします。取り込み済みの記録はそのまま残します。
    func disable() {
        isEnabled = false
        status = .idle
        activitySummary = nil
    }

    // MARK: - 同期

    /// ヘルスケアの体重と運動量を読み取り、アプリの記録に反映します。
    func sync(context: ModelContext) async {
        guard isEnabled, isAvailable, !isSyncing else { return }
        status = .syncing
        do {
            let importedCount = try await syncWeights(context: context)
            await syncExercise(context: context)
            try context.save()
            status = .finished(at: .now, importedWeightCount: importedCount)
        } catch {
            status = .failed(message: String(localized: "ヘルスケアとの同期に失敗しました。時間をおいて試してください。"))
        }
    }

    /// 体重：前回の同期から後の追加・削除を反映し、取り込んだ件数を返します。
    private func syncWeights(context: ModelContext) async throws -> Int {
        let changes = try await service.fetchWeightChanges(anchorData: defaults.data(forKey: Keys.weightAnchor))

        let entries = try context.fetch(FetchDescriptor<WeightEntry>())
        let plan = HealthWeightImportPlanner.plan(
            added: changes.added,
            deletedIDs: changes.deletedIDs,
            existing: entries.map {
                ExistingWeightRecord(
                    date: $0.date,
                    weightKg: $0.weightKg,
                    healthKitSampleID: $0.healthKitSampleID,
                    importedFromHealthKit: $0.importedFromHealthKit
                )
            }
        )

        for sample in plan.samplesToImport {
            context.insert(WeightEntry(
                date: sample.date,
                weightKg: sample.weightKg,
                healthKitSampleID: sample.id,
                importedFromHealthKit: true
            ))
        }
        for entry in entries {
            guard let id = entry.healthKitSampleID else { continue }
            if plan.importedIDsToDelete.contains(id) {
                context.delete(entry)
            } else if plan.writtenIDsToUnlink.contains(id) {
                entry.healthKitSampleID = nil
            }
        }

        // アプリ側に反映し終えてから「しおり」を進める（途中で失敗したら、次回もう一度読み直せるように）
        try context.save()
        if let newAnchorData = changes.newAnchorData {
            defaults.set(newAnchorData, forKey: Keys.weightAnchor)
        }
        return plan.samplesToImport.count
    }

    /// 運動：直近の運動量から、カレンダーの運動スタンプを押す・外す。
    private func syncExercise(context: ModelContext) async {
        let today = Date.now
        let start = DayMath.date(byAddingDays: -(Self.exerciseLookbackDays - 1), to: today, calendar: calendar)
        let activities = await service.fetchDailyActivity(from: start, through: today, calendar: calendar)

        let existing = (try? context.fetch(FetchDescriptor<ExerciseDay>(
            predicate: #Predicate { $0.date >= start }
        ))) ?? []
        let changes = ExerciseStampSyncPlanner.changes(
            activities: activities,
            existing: existing.map {
                ExistingExerciseStamp(day: $0.date, isFromHealthKit: $0.source == .healthKit, activeMinutes: $0.activeMinutes)
            },
            calendar: calendar
        )

        for change in changes {
            switch change {
            case .add(let day, let minutes):
                context.insert(ExerciseDay(date: day, source: .healthKit, activeMinutes: minutes))
            case .updateMinutes(let day, let minutes):
                for stamp in existing where stamp.source == .healthKit && calendar.isDate(stamp.date, inSameDayAs: day) {
                    stamp.activeMinutes = minutes
                }
            case .remove(let day):
                for stamp in existing where stamp.source == .healthKit && calendar.isDate(stamp.date, inSameDayAs: day) {
                    context.delete(stamp)
                }
            }
        }

        let summaryDays = activities.suffix(Self.activitySummaryDays)
        activitySummary = ActivityLevelEstimator.summarize(Array(summaryDays))
    }

    // MARK: - アプリで入力した体重をヘルスケアへ

    /// アプリで入力した体重を、ヘルスケアにも書き込みます（設定でオンのときだけ）。
    /// 書き込めたら、ヘルスケア側の ID を記録に覚えておきます（重複取り込みの防止と、削除の反映のため）。
    func exportNewEntry(_ entry: WeightEntry) async {
        guard isEnabled, writesWeightToHealth, isAvailable, service.canWriteWeight else { return }
        do {
            entry.healthKitSampleID = try await service.saveWeight(weightKg: entry.weightKg, date: entry.date)
        } catch {
            // 書き込めなくても、アプリの記録は残っているので、ここでは何もしない
        }
    }

    /// アプリで記録を削除するとき、このアプリがヘルスケアに書き込んだ分なら、ヘルスケアからも削除します。
    /// （ヘルスケアから取り込んだ記録は、ほかのアプリの記録なので、ヘルスケア側には残ります）
    func removeFromHealthIfNeeded(_ entry: WeightEntry) {
        guard isEnabled, isAvailable, !entry.importedFromHealthKit, let id = entry.healthKitSampleID else { return }
        service.deleteWeight(id: id)
    }
}
