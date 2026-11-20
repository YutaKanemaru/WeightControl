import Foundation

/// ヘルスケアから届いた体重の記録 1 件分（HealthKit の型を Logic に持ち込まないための「値の型」）。
nonisolated struct HealthWeightSample: Equatable, Sendable {
    /// ヘルスケア側の ID（サンプルごとに一意）
    let id: UUID
    /// 測った日時
    let date: Date
    /// 体重（kg）
    let weightKg: Double
    /// このアプリ自身がヘルスケアに書き込んだ記録か（自分の書いたものを取り込み直さないため）
    let isFromThisApp: Bool
}

/// アプリに保存済みの体重の記録（`WeightEntry` から必要な値だけを抜き出したもの）。
nonisolated struct ExistingWeightRecord: Equatable, Sendable {
    let date: Date
    let weightKg: Double
    let healthKitSampleID: UUID?
    let importedFromHealthKit: Bool
}

/// 取り込みで何をするかの計画。実際の保存・削除は画面側（SwiftData）で行います。
nonisolated struct HealthWeightImportPlan: Equatable, Sendable {
    /// 新しくアプリに保存する記録（日時の古い順）
    var samplesToImport: [HealthWeightSample] = []
    /// ヘルスケアで消された「取り込み済み」の記録の ID。アプリからも消します。
    var importedIDsToDelete: Set<UUID> = []
    /// ヘルスケアで消された「アプリで入力して書き込んだ」記録の ID。
    /// アプリの記録は消さずに残し、ヘルスケアとのつながり（ID）だけを外します。
    var writtenIDsToUnlink: Set<UUID> = []
}

/// ヘルスケアの体重をアプリに取り込むときの「重複を防ぐルール」。
///
/// 重複とみなすのは次のどれかです。
/// 1. このアプリ自身が書き込んだ記録（アプリにはもうある）
/// 2. 同じ ID の記録がアプリにすでにある
/// 3. 時刻が 10 分以内で、体重の差が 0.05 kg 以内の記録がすでにある
///    （体重計アプリとこのアプリの両方に手で入力した、などのケース）
nonisolated enum HealthWeightImportPlanner {
    /// 「ほぼ同じ時刻」とみなす幅（秒）
    static let duplicateTimeWindow: TimeInterval = 10 * 60
    /// 「ほぼ同じ体重」とみなす差（kg）
    static let duplicateWeightToleranceKg = 0.05

    /// - Parameters:
    ///   - added: ヘルスケアで追加された記録（前回の同期から後のもの）
    ///   - deletedIDs: ヘルスケアで削除された記録の ID
    ///   - existing: アプリに保存済みの記録
    static func plan(
        added: [HealthWeightSample],
        deletedIDs: Set<UUID>,
        existing: [ExistingWeightRecord]
    ) -> HealthWeightImportPlan {
        var plan = HealthWeightImportPlan()

        // 比べる相手：アプリにある記録 ＋ 今回取り込むと決めた記録
        var knownIDs = Set(existing.compactMap(\.healthKitSampleID))
        var knownPoints = existing.map { (date: $0.date, weightKg: $0.weightKg) }

        for sample in added.sorted(by: { $0.date < $1.date }) {
            if sample.isFromThisApp || knownIDs.contains(sample.id) {
                continue
            }
            // 打ち間違いのような値は、手入力と同じ範囲ではじく
            if !WeightInputParser.validRangeKg.contains(sample.weightKg) {
                continue
            }
            let isNearDuplicate = knownPoints.contains { point in
                abs(point.date.timeIntervalSince(sample.date)) <= duplicateTimeWindow
                    && abs(point.weightKg - sample.weightKg) <= duplicateWeightToleranceKg + 1e-9
            }
            if isNearDuplicate {
                continue
            }
            plan.samplesToImport.append(sample)
            knownIDs.insert(sample.id)
            knownPoints.append((date: sample.date, weightKg: sample.weightKg))
        }

        for record in existing {
            guard let id = record.healthKitSampleID, deletedIDs.contains(id) else { continue }
            if record.importedFromHealthKit {
                plan.importedIDsToDelete.insert(id)
            } else {
                plan.writtenIDsToUnlink.insert(id)
            }
        }

        return plan
    }
}
