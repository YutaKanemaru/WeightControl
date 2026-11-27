import Foundation

/// Watch で記録して、まだ iPhone から「受け取りました」が返ってきていない記録（送信待ち）を保存する係。
///
/// Watch アプリとコンプリケーションの両方が読むので、Watch の中の App Group の `UserDefaults` に置きます
/// （`WidgetSnapshotStore` と同じ引き出し。Watch の App Group は Watch の中だけのもので、iPhone とは共有されません）。
nonisolated struct WatchPendingStore: Sendable {
    /// 保存するときのキー
    static let pendingKey = "watch.pendingRecords"

    let suiteName: String

    init(suiteName: String = WidgetSnapshotStore.appGroupID) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// 保存されている送信待ち（古い順）。ない・読めないときは空。
    func load() -> [WatchWeightRecord] {
        guard let data = defaults?.data(forKey: Self.pendingKey),
              let records = try? JSONDecoder().decode([WatchWeightRecord].self, from: data)
        else { return [] }
        return records
    }

    func save(_ records: [WatchWeightRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: Self.pendingKey)
    }
}
