import Foundation
import Testing
@testable import WeightControlApp

/// Apple Watch から届いた記録を足すかどうかのルール（Logic/Watch/WatchRecordImportPlanner）のテスト。
struct WatchRecordImportPlannerTests {
    private func day(_ n: Int, hour: Int = 0) -> Date { TestCalendar.day(n, hour: hour) }
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test("はじめて届いた記録は、そのまま足す")
    func insertsNewRecord() {
        let record = WatchWeightRecord(id: id, date: day(0, hour: 7), weightKg: 64.2)
        #expect(WatchRecordImportPlanner.decide(record: record, processedIDs: [], now: day(0, hour: 8))
            == .insert(date: day(0, hour: 7), weightKg: 64.2))
    }

    @Test("同じ ID の記録は 2 回足さない")
    func skipsDuplicate() {
        let record = WatchWeightRecord(id: id, date: day(0, hour: 7), weightKg: 64.2)
        #expect(WatchRecordImportPlanner.decide(record: record, processedIDs: [UUID(), id], now: day(0, hour: 8)) == .duplicate)
    }

    @Test("体重は小数第 1 位に丸める")
    func roundsWeight() {
        let record = WatchWeightRecord(id: id, date: day(0), weightKg: 64.2999999)
        #expect(WatchRecordImportPlanner.decide(record: record, processedIDs: [], now: day(0)) == .insert(date: day(0), weightKg: 64.3))
    }

    @Test("iPhone の入力画面と同じ範囲（20〜300 kg）の外は足さない")
    func rejectsOutOfRange() {
        let low = WatchWeightRecord(id: id, date: day(0), weightKg: 19.9)
        let high = WatchWeightRecord(id: UUID(), date: day(0), weightKg: 300.1)
        #expect(WatchRecordImportPlanner.decide(record: low, processedIDs: [], now: day(0)) == .outOfRange)
        #expect(WatchRecordImportPlanner.decide(record: high, processedIDs: [], now: day(0)) == .outOfRange)
    }

    @Test("未来の日時の記録は、受け取った日時にそろえる")
    func clampsFutureDate() {
        let record = WatchWeightRecord(id: id, date: day(0, hour: 9), weightKg: 64.0)
        #expect(WatchRecordImportPlanner.decide(record: record, processedIDs: [], now: day(0, hour: 8))
            == .insert(date: day(0, hour: 8), weightKg: 64.0))
    }

    @Test("ID は重ねて覚えず、上限を超えたら古いものから忘れる")
    func remembersWithLimit() {
        let ids = (0..<WatchRecordImportPlanner.rememberedIDLimit).map { _ in UUID() }
        let again = WatchRecordImportPlanner.remembering(ids[0], in: ids)
        #expect(again.count == ids.count)
        #expect(again.last == ids[0])

        let added = WatchRecordImportPlanner.remembering(id, in: ids)
        #expect(added.count == WatchRecordImportPlanner.rememberedIDLimit)
        #expect(added.first == ids[1])
        #expect(added.last == id)
    }

    @Test("Watch に返す受け取り済みの ID は、新しいほうから上限まで")
    func acknowledgedIDs() {
        let ids = (0..<30).map { _ in UUID() }
        let acknowledged = WatchRecordImportPlanner.acknowledgedIDs(from: ids)
        #expect(acknowledged == Array(ids.suffix(WatchRecordImportPlanner.acknowledgedIDLimit)))
        #expect(WatchRecordImportPlanner.acknowledgedIDs(from: []) == [])
    }
}
