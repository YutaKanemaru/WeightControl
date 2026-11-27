import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Watch 側の、iPhone とやりとりする係。仕様は docs/WATCH.md の「データの受け渡し」。
///
/// - iPhone から届いたスナップショットを保存して、画面とコンプリケーションに出す。
/// - Watch で記録した体重を iPhone に送る。iPhone が近くにあれば `sendMessage`（すぐ届く）、
///   なければ・失敗したら `transferUserInfo`（つながったときに順番に届く）。
/// - iPhone から「受け取りました」が返ってくるまでは「送信待ち」として残し、画面に「iPhone に送信待ち」と出す。
///
/// `@Observable` なので、値が変わると画面が自動で描き直されます。
@Observable
final class PhoneConnection: NSObject {
    /// iPhone から届いた最新のスナップショット。まだ一度も届いていなければ nil。
    private(set) var snapshot: WidgetSnapshot?
    /// 送信待ちの記録（古い順）
    private(set) var pending: [WatchWeightRecord]

    @ObservationIgnored private let snapshotStore = WidgetSnapshotStore()
    @ObservationIgnored private let pendingStore = WatchPendingStore()

    override init() {
        snapshot = snapshotStore.load()
        pending = pendingStore.load()
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 画面に出す内容（表示する日に合わせて数える）
    func summary(today: Date = .now) -> WatchSummary {
        WatchSummary(snapshot: snapshot, pending: pending, today: today)
    }

    // MARK: - 記録する

    /// 体重を記録して iPhone に送る
    func record(weightKg: Double, now: Date = .now) {
        let record = WatchWeightRecord(id: UUID(), date: now, weightKg: WatchDisplay.rounded(weightKg))
        pending.append(record)
        savePending()
        send(record)
    }

    private func send(_ record: WatchWeightRecord) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            // まだつながっていない。つながったとき（`activationDidCompleteWith`）に送信待ちをまとめて送る
            return
        }
        let payload = WatchMessage.payload(for: record)
        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: { [weak self] reply in
            let snapshot = WatchMessage.snapshot(from: reply)
            let ids = WatchMessage.acknowledgedIDs(from: reply)
            Task { @MainActor in self?.apply(snapshot: snapshot, acknowledgedIDs: ids) }
        }, errorHandler: { _ in
            // すぐには届かなかったので、届くまで待つ送り方で送り直す（iPhone は同じ ID を 2 回足さない）
            WCSession.default.transferUserInfo(payload)
        })
    }

    /// まだ届いていない送信待ちを、届くまで待つ送り方でもう一度送る（アプリを閉じている間に送りそびれたものなど）
    private func resendPending() {
        let session = WCSession.default
        let queuedIDs = Set(session.outstandingUserInfoTransfers.compactMap { WatchMessage.record(from: $0.userInfo)?.id })
        for record in pending where !queuedIDs.contains(record.id) {
            session.transferUserInfo(WatchMessage.payload(for: record))
        }
    }

    // MARK: - iPhone から届いたもの

    private func apply(snapshot newSnapshot: WidgetSnapshot?, acknowledgedIDs: Set<UUID>) {
        if let newSnapshot {
            snapshot = newSnapshot
            snapshotStore.save(newSnapshot)
        }
        pending = WatchDisplay.remainingPending(pending, acknowledgedIDs: acknowledgedIDs, now: .now)
        savePending()
    }

    private func savePending() {
        pendingStore.save(pending)
        // コンプリケーションも描き直してもらう
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - WCSessionDelegate

// WatchConnectivity は、これらの関数を裏のスレッドから呼ぶので `nonisolated` を付け、
// `Task { @MainActor in ... }` でメインスレッドに戻ってから値を変えます。
extension PhoneConnection: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        let snapshot = WatchMessage.snapshot(from: context)
        let ids = WatchMessage.acknowledgedIDs(from: context)
        Task { @MainActor in
            self.apply(snapshot: snapshot, acknowledgedIDs: ids)
            self.resendPending()
        }
    }

    /// iPhone が `updateApplicationContext` で送ったスナップショット
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let snapshot = WatchMessage.snapshot(from: applicationContext)
        let ids = WatchMessage.acknowledgedIDs(from: applicationContext)
        Task { @MainActor in
            self.apply(snapshot: snapshot, acknowledgedIDs: ids)
        }
    }
}
