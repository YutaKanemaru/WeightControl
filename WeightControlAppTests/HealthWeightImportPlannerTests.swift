import Foundation
import Testing
@testable import WeightControlApp

/// ヘルスケアの体重を取り込むときの重複防止ルール（HealthWeightImportPlanner）のテスト
struct HealthWeightImportPlannerTests {

    private func sample(_ day: Int, hour: Int = 7, weightKg: Double, fromThisApp: Bool = false, id: UUID = UUID()) -> HealthWeightSample {
        HealthWeightSample(id: id, date: TestCalendar.day(day, hour: hour), weightKg: weightKg, isFromThisApp: fromThisApp)
    }

    private func record(_ day: Int, hour: Int = 7, weightKg: Double, id: UUID? = nil, imported: Bool = false) -> ExistingWeightRecord {
        ExistingWeightRecord(date: TestCalendar.day(day, hour: hour), weightKg: weightKg, healthKitSampleID: id, importedFromHealthKit: imported)
    }

    @Test("新しい記録は、日時の古い順に取り込む")
    func importsNewSamplesInDateOrder() {
        let later = sample(2, weightKg: 64.8)
        let earlier = sample(1, weightKg: 65.0)
        let plan = HealthWeightImportPlanner.plan(added: [later, earlier], deletedIDs: [], existing: [])
        #expect(plan.samplesToImport == [earlier, later])
    }

    @Test("このアプリが書き込んだ記録は取り込まない")
    func skipsOwnSamples() {
        let plan = HealthWeightImportPlanner.plan(
            added: [sample(1, weightKg: 65.0, fromThisApp: true)], deletedIDs: [], existing: []
        )
        #expect(plan.samplesToImport.isEmpty)
    }

    @Test("同じ ID の記録がすでにあれば取り込まない")
    func skipsKnownID() {
        let id = UUID()
        let plan = HealthWeightImportPlanner.plan(
            added: [sample(1, weightKg: 65.0, id: id)],
            deletedIDs: [],
            existing: [record(5, weightKg: 70.0, id: id)]
        )
        #expect(plan.samplesToImport.isEmpty)
    }

    @Test("10 分以内・0.05 kg 以内の記録があれば重複とみなす")
    func skipsNearDuplicate() {
        let existing = [record(1, hour: 7, weightKg: 65.0)]
        let nearby = HealthWeightSample(
            id: UUID(), date: TestCalendar.day(1, hour: 7).addingTimeInterval(9 * 60), weightKg: 65.05, isFromThisApp: false
        )
        let plan = HealthWeightImportPlanner.plan(added: [nearby], deletedIDs: [], existing: existing)
        #expect(plan.samplesToImport.isEmpty)
    }

    @Test("時刻か体重が離れていれば別の記録として取り込む")
    func importsWhenNotNearDuplicate() {
        let existing = [record(1, hour: 7, weightKg: 65.0)]
        let laterSameWeight = sample(1, hour: 8, weightKg: 65.0)
        let sameTimeDifferentWeight = HealthWeightSample(
            id: UUID(), date: TestCalendar.day(1, hour: 7), weightKg: 65.2, isFromThisApp: false
        )
        let plan = HealthWeightImportPlanner.plan(
            added: [laterSameWeight, sameTimeDifferentWeight], deletedIDs: [], existing: existing
        )
        #expect(plan.samplesToImport.count == 2)
    }

    @Test("今回届いた記録どうしの重複も 1 件にまとめる")
    func dedupesWithinBatch() {
        let first = sample(1, weightKg: 65.0)
        let copy = sample(1, weightKg: 65.0)
        let plan = HealthWeightImportPlanner.plan(added: [first, copy], deletedIDs: [], existing: [])
        #expect(plan.samplesToImport.count == 1)
    }

    @Test("ありえない体重（20〜300 kg の外）は取り込まない")
    func skipsOutOfRange() {
        let plan = HealthWeightImportPlanner.plan(
            added: [sample(1, weightKg: 6.5), sample(2, weightKg: 650)], deletedIDs: [], existing: []
        )
        #expect(plan.samplesToImport.isEmpty)
    }

    @Test("ヘルスケアで消された記録：取り込んだものは削除、アプリで入力したものはつながりだけ外す")
    func handlesDeletions() {
        let importedID = UUID()
        let writtenID = UUID()
        let unrelatedID = UUID()
        let plan = HealthWeightImportPlanner.plan(
            added: [],
            deletedIDs: [importedID, writtenID, UUID()],
            existing: [
                record(1, weightKg: 65.0, id: importedID, imported: true),
                record(2, weightKg: 64.8, id: writtenID, imported: false),
                record(3, weightKg: 64.6, id: unrelatedID, imported: true),
                record(4, weightKg: 64.5),
            ]
        )
        #expect(plan.importedIDsToDelete == [importedID])
        #expect(plan.writtenIDsToUnlink == [writtenID])
    }
}
