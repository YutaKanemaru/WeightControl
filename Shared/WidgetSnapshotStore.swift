import Foundation

/// `WidgetSnapshot` を App Group の `UserDefaults` に読み書きする係（アプリとウィジェットの両方で使う）。
///
/// App Group（`group.com.utahengineering.weightforecast`）は、同じ開発者のアプリと拡張だけが使える共有の保存場所です。
/// アプリとウィジェットは別々の箱（サンドボックス）で動いているので、ふつうの `UserDefaults.standard` ではお互いに読めません。
/// `UserDefaults(suiteName:)` に App Group の名前を渡すと、共有の引き出しを開けます。
nonisolated struct WidgetSnapshotStore: Sendable {
    /// App Group の名前。アプリと拡張の entitlements（できることの許可リスト）にも同じ名前を書いています。
    static let appGroupID = "group.com.utahengineering.weightforecast"
    /// 保存するときのキー
    static let snapshotKey = "widget.snapshot"

    /// 読み書きする `UserDefaults` の名前（テストでは別の名前を渡して、本物のデータに触らないようにする）
    let suiteName: String

    init(suiteName: String = WidgetSnapshotStore.appGroupID) {
        self.suiteName = suiteName
    }

    /// 共有の引き出し。App Group が使えない（署名なしのビルドなど）ときは nil。
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// 保存されているスナップショット。まだない・読めない・古い形のときは nil。
    func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    /// 保存する。書けなかったら何もしない（ウィジェットが前の表示のままになるだけで、アプリの動きには影響しない）。
    func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Self.snapshotKey)
    }
}
