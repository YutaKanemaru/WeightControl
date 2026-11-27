import Foundation

/// Apple Watch から届いた記録を、iPhone の記録に足すかどうかを決めるルール。仕様は docs/WATCH.md。
///
/// Watch は、近くに iPhone があればすぐ届く送り方（`sendMessage`）で送り、だめなら届くまで待つ送り方（`transferUserInfo`）で
/// 送り直します。そのため、同じ記録が 2 回届くことがあります。記録の ID を覚えておいて、同じ ID は足しません。
nonisolated enum WatchRecordImportPlanner {
    /// 覚えておく ID の数（古いものから忘れる）
    static let rememberedIDLimit = 200
    /// Watch に「受け取りました」と返す ID の数（新しいほうから）
    static let acknowledgedIDLimit = 20

    /// 届いた記録をどうするか
    enum Decision: Equatable {
        /// 記録として足す（日時と体重は、ここで整えた値を使う）
        case insert(date: Date, weightKg: Double)
        /// もう足した記録なので足さない
        case duplicate
        /// 記録できない体重なので足さない（iPhone の入力画面と同じ範囲で判断）
        case outOfRange
    }

    /// - Parameters:
    ///   - record: Watch から届いた記録
    ///   - processedIDs: これまでに受け取った記録の ID
    ///   - now: 受け取った日時（未来の日時の記録は、この日時にそろえる）
    static func decide(record: WatchWeightRecord, processedIDs: [UUID], now: Date) -> Decision {
        if processedIDs.contains(record.id) { return .duplicate }
        let weightKg = (record.weightKg * 10).rounded() / 10
        guard WeightInputParser.validRangeKg.contains(weightKg) else { return .outOfRange }
        // Watch と iPhone の時計がずれていて、未来の記録にならないように
        return .insert(date: min(record.date, now), weightKg: weightKg)
    }

    /// 受け取った ID を覚える。同じ ID は 2 回入れず、`rememberedIDLimit` を超えたら古いものから忘れる。
    static func remembering(_ id: UUID, in processedIDs: [UUID]) -> [UUID] {
        var result = processedIDs.filter { $0 != id }
        result.append(id)
        return Array(result.suffix(rememberedIDLimit))
    }

    /// Watch に返す「受け取り済み」の ID（新しく受け取ったものから `acknowledgedIDLimit` 件）
    static func acknowledgedIDs(from processedIDs: [UUID]) -> [UUID] {
        Array(processedIDs.suffix(acknowledgedIDLimit))
    }
}
