import Foundation
import SwiftData

/// 体重の記録 1 件分。
///
/// `@Model` を付けると、SwiftData がこのクラスを「端末内のデータベースに保存できる形」として扱います。
/// プロパティ（`date`, `weightKg`）がそのままデータベースの列になります。
/// ここには「保存する形」だけを書き、計算は `Logic/` に置きます。
@Model
final class WeightEntry {
    /// 測った日時
    var date: Date
    /// 体重（kg）
    var weightKg: Double
    /// ヘルスケア（HealthKit）側の同じ記録の ID。
    ///
    /// - ヘルスケアから取り込んだ記録：取り込み元のサンプルの ID
    /// - アプリで入力してヘルスケアにも書き込んだ記録：書き込んだサンプルの ID
    /// - ヘルスケアと関係ない記録：nil
    ///
    /// 同じ記録を 2 回取り込まないため（重複防止）と、削除を両方に反映するために使います。
    /// 後から追加した列ですが、nil を許すので、保存済みの記録はそのまま読み込めます（SwiftData が自動で移行）。
    var healthKitSampleID: UUID?
    /// ヘルスケアから取り込んだ記録なら true（アプリで入力した記録は false）。
    /// 既定値があるので、保存済みの記録は自動で false として扱われます。
    var importedFromHealthKit: Bool = false

    init(date: Date, weightKg: Double, healthKitSampleID: UUID? = nil, importedFromHealthKit: Bool = false) {
        self.date = date
        self.weightKg = weightKg
        self.healthKitSampleID = healthKitSampleID
        self.importedFromHealthKit = importedFromHealthKit
    }
}
