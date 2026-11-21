import Foundation
import SwiftData

/// 「この日はチートデーにする」と決めた日 1 件分（Pro 機能・フェーズ 12）。
///
/// ホームの「チートデー」カードで、アプリの提案から日を選ぶと保存されます。
/// 「週 2 日まで」の数え方、カレンダーのスタンプ、当日の摂取カロリーの目安（維持カロリーで表示）に使います。
/// 決まりは docs/CHEAT_DAY.md。
@Model
final class CheatDay {
    /// チートデーにした日。時刻は使わないので、いつも「その日の 0 時」にそろえて保存します。
    var date: Date
    /// この記録を作った日時
    var createdAt: Date

    init(date: Date, createdAt: Date = .now) {
        self.date = date
        self.createdAt = createdAt
    }
}
