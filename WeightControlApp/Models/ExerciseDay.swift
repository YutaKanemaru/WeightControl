import Foundation
import SwiftData

/// 「この日は運動した」という記録 1 件分（カレンダーの運動スタンプ）。
///
/// いまはカレンダーの日付をタップして自分で押す（`source == .manual`）だけですが、
/// フェーズ 7 で HealthKit（ヘルスケア）から運動量を取り込むときにも、同じ型に保存できるようにしてあります。
/// そのときは `source` を `.healthKit` にして、運動した分数（`activeMinutes`）も入れる想定です。
@Model
final class ExerciseDay {
    /// 運動した日。時刻は使わないので、いつも「その日の 0 時」にそろえて保存します。
    var date: Date
    /// 記録のつけ方（`Source` の rawValue）。手動か、HealthKit からの自動取り込みか。
    var sourceRawValue: String
    /// 運動した時間（分）。手動のスタンプでは nil。HealthKit から取り込むときに使う予定です。
    var activeMinutes: Int?
    /// この記録を作った日時
    var createdAt: Date

    init(date: Date, source: Source = .manual, activeMinutes: Int? = nil, createdAt: Date = .now) {
        self.date = date
        self.sourceRawValue = source.rawValue
        self.activeMinutes = activeMinutes
        self.createdAt = createdAt
    }

    /// 記録のつけ方。保存されている文字列から変換して返します（読めない値なら `.manual`）。
    var source: Source {
        get { Source(rawValue: sourceRawValue) ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }
}

extension ExerciseDay {
    /// 運動スタンプのつけ方
    nonisolated enum Source: String, CaseIterable, Sendable {
        /// カレンダーで自分でタップして押した
        case manual
        /// HealthKit（ヘルスケア）から自動で取り込んだ（フェーズ 7 で使う予定）
        case healthKit
    }
}
