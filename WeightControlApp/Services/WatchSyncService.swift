import Foundation
import SwiftData
import WatchConnectivity

/// iPhone 側の、Apple Watch とやりとりする窓口。仕様は docs/WATCH.md。
///
/// WatchConnectivity（iPhone と Watch が Bluetooth や Wi-Fi で直接やりとりする Apple 純正のしくみ）の `WCSession` を使います。
/// データは外のサーバーを通りません。
///
/// - iPhone → Watch：ウィジェットと同じスナップショットを `updateApplicationContext` で送る（「いまの状態」を 1 つだけ送る送り方。
///   新しいものを送ると古いものは捨てられる）。いっしょに「受け取り済みの記録の ID」も送り、Watch はそれを見て「送信待ち」を消します。
/// - Watch → iPhone：Watch で記録した体重が届いたら、`WeightEntry` として足し、ヘルスケア連携がオンならヘルスケアにも書きます
///   （iPhone の入力画面と同じ）。足すかどうかの判断は `Logic/Watch/WatchRecordImportPlanner`。
///
/// Watch から記録が届くと、iPhone のアプリが閉じていても iOS が裏で起こしてくれます。そのときは画面がないので、
/// アプリの起動時（`WeightControlAppApp` の init）にこの係を作って `activate()` しておきます。
final class WatchSyncService: NSObject {
    /// アプリで 1 つだけ。`WidgetSnapshotPublisher` がスナップショットを送るときに使う
    private(set) static var shared: WatchSyncService?

    private let container: ModelContainer
    private let health: HealthSyncController
    private let pro: ProAccess
    private let defaults: UserDefaults

    private enum Keys {
        /// これまでに受け取った Watch の記録の ID（重複防止用）
        static let processedIDs = "watch.processedRecordIDs"
    }

    init(container: ModelContainer, health: HealthSyncController, pro: ProAccess, defaults: UserDefaults = .standard) {
        self.container = container
        self.health = health
        self.pro = pro
        self.defaults = defaults
        super.init()
    }

    /// WatchConnectivity を使い始める（Watch がない iPhone では何もしない）
    func activate() {
        guard WCSession.isSupported() else { return }
        Self.shared = self
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - iPhone → Watch

    /// スナップショットを Watch に送る。Watch がない・Watch アプリが入っていないときは何もしない。
    func sendSnapshot(_ snapshot: WidgetSnapshot?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchMessage.payload(
            snapshot: snapshot,
            acknowledgedIDs: WatchRecordImportPlanner.acknowledgedIDs(from: processedIDs)
        )
        // 送れなくても（Watch の電源が切れているなど）、次に記録や目標が変わったときにまた送るので、ここでは何もしない
        try? session.updateApplicationContext(payload)
    }

    // MARK: - Watch → iPhone

    /// Watch から届いた記録を足して、新しいスナップショットを返す
    private func receive(_ record: WatchWeightRecord) -> WidgetSnapshot {
        let context = container.mainContext
        let now = Date.now
        let ids = processedIDs
        switch WatchRecordImportPlanner.decide(record: record, processedIDs: ids, now: now) {
        case .insert(let date, let weightKg):
            let entry = WeightEntry(date: date, weightKg: weightKg)
            context.insert(entry)
            // アプリが裏で起こされたときは自動保存を待たずに終わることがあるので、ここで保存しておく
            try? context.save()
            processedIDs = WatchRecordImportPlanner.remembering(record.id, in: ids)
            // 設定でオンなら、ヘルスケアにも書き込む（iPhone の入力画面と同じ）
            let health = health
            Task { await health.exportNewEntry(entry) }
        case .duplicate:
            break
        case .outOfRange:
            // 足さないが、Watch の「送信待ち」は消してもらう
            processedIDs = WatchRecordImportPlanner.remembering(record.id, in: ids)
        }
        let snapshot = WidgetSnapshotPublisher.publish(context: context, isProUnlocked: pro.isUnlocked, now: now)
        // 中身が前と同じでも、受け取り済みの ID を Watch に知らせるために送る
        sendSnapshot(snapshot)
        return snapshot
    }

    private var processedIDs: [UUID] {
        get { (defaults.stringArray(forKey: Keys.processedIDs) ?? []).compactMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue.map(\.uuidString), forKey: Keys.processedIDs) }
    }

    private func acknowledgementPayload(snapshot: WidgetSnapshot) -> [String: Any] {
        WatchMessage.payload(snapshot: snapshot, acknowledgedIDs: WatchRecordImportPlanner.acknowledgedIDs(from: processedIDs))
    }
}

// MARK: - WCSessionDelegate

// WatchConnectivity は、これらの関数を裏のスレッドから呼びます。そのため `nonisolated`（メインスレッド専用にしない）を付け、
// 中で `Task { @MainActor in ... }` を使ってメインスレッドに戻ってから、SwiftData などを触ります。
extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            // つながったら、まず最新のスナップショットを送っておく
            self.sendSnapshot(WidgetSnapshotPublisher.latest)
        }
    }

    /// Watch を付けかえたときなどに呼ばれる（iPhone だけにある関数）
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// 付けかえが終わったら、新しい Watch とつながり直す
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Watch アプリを入れた・ペアリングしたときに、最新のスナップショットを送る
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.sendSnapshot(WidgetSnapshotPublisher.latest)
        }
    }

    /// すぐ届く送り方（`sendMessage`）で、返事を待っている記録
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let record = WatchMessage.record(from: message) else {
            replyHandler([:])
            return
        }
        // 返事の関数は WatchConnectivity が用意したもので、どのスレッドから呼んでもよい
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let snapshot = self.receive(record)
            reply(self.acknowledgementPayload(snapshot: snapshot))
        }
    }

    /// 届くまで待つ送り方（`transferUserInfo`）で届いた記録
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let record = WatchMessage.record(from: userInfo) else { return }
        Task { @MainActor in
            _ = self.receive(record)
        }
    }
}
