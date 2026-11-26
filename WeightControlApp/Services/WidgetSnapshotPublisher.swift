import Foundation
import WidgetKit

/// ウィジェットに出す数字（`WidgetSnapshot`）を App Group に保存して、ウィジェットに「描き直して」と知らせる係。
///
/// `WidgetCenter`（WidgetKit の窓口）の `reloadAllTimelines()` を呼ぶと、
/// iPhone がウィジェットの拡張を動かして、新しい表示の予定表（タイムライン）を受け取り直します。
/// 描き直しは iPhone の都合で少し遅れることがありますが、アプリが前面にあるときはすぐに反映されます。
enum WidgetSnapshotPublisher {
    private static let store = WidgetSnapshotStore()

    /// スナップショットを保存する。前に保存したものと同じなら、何もしない（描き直しの回数を減らすため）。
    static func publish(_ snapshot: WidgetSnapshot) {
        if let saved = store.load(), saved.isSameContent(as: snapshot) { return }
        store.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension WidgetSnapshot {
    /// 作った日時以外が同じか
    func isSameContent(as other: WidgetSnapshot) -> Bool {
        var copy = other
        copy.generatedAt = generatedAt
        return copy == self
    }
}
