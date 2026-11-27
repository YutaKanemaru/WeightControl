import Foundation

// Apple Watch と iPhone のあいだでやりとりするデータの形（仕様は docs/WATCH.md）。
// このファイルは Shared/ にあるので、iPhone アプリ・ウィジェット・Watch アプリ・コンプリケーションのすべてに入ります。

/// Watch で記録した体重 1 件分。Watch → iPhone へ送る。
nonisolated struct WatchWeightRecord: Codable, Equatable, Sendable, Identifiable {
    /// 同じ記録を 2 回足さないための ID（Watch で記録したときに作る）
    var id: UUID
    /// Watch で「記録する」を押した日時
    var date: Date
    /// 体重（kg、小数 1 桁）
    var weightKg: Double
}

/// WatchConnectivity（iPhone と Watch で直接やりとりする Apple 純正のしくみ）で送る辞書のキーと、詰め方・取り出し方。
///
/// WatchConnectivity は `[String: Any]` の辞書で送ります。中身は JSON にした `Data` にして、
/// 両方の側で同じ Codable の型で読み書きするので、形がずれません。
nonisolated enum WatchMessage {
    /// Watch → iPhone：記録（`WatchWeightRecord` の JSON）
    static let recordKey = "record"
    /// iPhone → Watch：ウィジェットと同じスナップショット（`WidgetSnapshot` の JSON）
    static let snapshotKey = "snapshot"
    /// iPhone → Watch：iPhone が受け取り終えた記録の ID（文字列の配列）。Watch はこれを見て「送信待ち」から消す
    static let acknowledgedIDsKey = "acknowledgedIDs"

    /// 記録を送る辞書にする
    static func payload(for record: WatchWeightRecord) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(record) else { return [:] }
        return [recordKey: data]
    }

    /// 受け取った辞書から記録を取り出す。形がちがえば nil。
    static func record(from payload: [String: Any]) -> WatchWeightRecord? {
        guard let data = payload[recordKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchWeightRecord.self, from: data)
    }

    /// スナップショットと受け取り済みの ID を送る辞書にする
    static func payload(snapshot: WidgetSnapshot?, acknowledgedIDs: [UUID]) -> [String: Any] {
        var result: [String: Any] = [acknowledgedIDsKey: acknowledgedIDs.map(\.uuidString)]
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            result[snapshotKey] = data
        }
        return result
    }

    /// 受け取った辞書からスナップショットを取り出す。ない・古い形のときは nil。
    static func snapshot(from payload: [String: Any]) -> WidgetSnapshot? {
        guard let data = payload[snapshotKey] as? Data,
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    /// 受け取った辞書から、受け取り済みの ID を取り出す
    static func acknowledgedIDs(from payload: [String: Any]) -> Set<UUID> {
        let strings = payload[acknowledgedIDsKey] as? [String] ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }
}
