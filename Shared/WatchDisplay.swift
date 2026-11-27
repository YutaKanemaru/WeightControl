import Foundation

/// Apple Watch で体重を記録するときのルール（Watch アプリに入り、テストはアプリ側で行う）。仕様は docs/WATCH.md。
///
/// Watch には `Logic/` が入っていないので、iPhone の入力画面と同じ決まり（範囲・0.1 kg 刻み・2.0 kg の確認）を
/// ここにも置いています。値が iPhone 側とずれていないことは `WatchDisplayTests` で確かめています。
nonisolated enum WatchDisplay {
    /// 記録できる体重の範囲（kg）。iPhone の `WeightInputParser.validRangeKg` と同じ
    static let validRangeKg: ClosedRange<Double> = 20...300
    /// Digital Crown を 1 目盛り回したときに動く量（kg）。iPhone の「−」「＋」と同じ
    static let stepKg = 0.1
    /// 記録がまったくないときに、記録の画面で最初に出す体重（kg）
    static let defaultStartKg = 60.0
    /// 前回とこれ以上ちがえば確認する（kg）。iPhone の `WeightEntryCheck.largeChangeThresholdKg` と同じ
    static let largeChangeThresholdKg = 2.0
    /// 送信待ちがこれより古くなったら、表示から外す（日）。iPhone が届いた記録を受け取り損ねても、ずっと「送信待ち」が残らないように
    static let pendingExpiryDays = 7

    /// 小数第 1 位に丸めて、記録できる範囲におさめる（Digital Crown の値は 64.30000001 のようになることがあるため）
    static func rounded(_ kg: Double) -> Double {
        let value = (kg * 10).rounded() / 10
        return min(max(value, validRangeKg.lowerBound), validRangeKg.upperBound)
    }

    /// 記録の画面で最初に出す体重：いちばん新しい記録（送信待ちも含む）。なければ `defaultStartKg`
    static func startWeightKg(snapshot: WidgetSnapshot?, pending: [WatchWeightRecord]) -> Double {
        rounded(latest(snapshot: snapshot, pending: pending)?.weightKg ?? defaultStartKg)
    }

    /// 前回と大きくちがうなら、その差（kg、プラスは増加）。確認しなくてよければ nil。
    static func largeChange(newKg: Double, previousKg: Double?) -> Double? {
        guard let previousKg else { return nil }
        let diff = ((newKg - previousKg) * 10).rounded() / 10
        return abs(diff) >= largeChangeThresholdKg ? diff : nil
    }

    /// いちばん新しい記録。iPhone から届いた記録と、送信待ちのうち日時の新しいほう。
    static func latest(snapshot: WidgetSnapshot?, pending: [WatchWeightRecord]) -> LatestWeight? {
        let fromPhone: LatestWeight? = {
            guard let kg = snapshot?.latestWeightKg, let date = snapshot?.latestDate else { return nil }
            return LatestWeight(weightKg: kg, date: date, isPending: false)
        }()
        let fromWatch = pending.max { $0.date < $1.date }.map {
            LatestWeight(weightKg: $0.weightKg, date: $0.date, isPending: true)
        }
        switch (fromPhone, fromWatch) {
        case let (phone?, watch?):
            return watch.date > phone.date ? watch : phone
        case let (phone, watch):
            return phone ?? watch
        }
    }

    /// iPhone から返事が来たあとに残す送信待ち。受け取り済みの ID と、古くなりすぎたものを外す。
    static func remainingPending(
        _ pending: [WatchWeightRecord],
        acknowledgedIDs: Set<UUID>,
        now: Date,
        calendar: Calendar = .current
    ) -> [WatchWeightRecord] {
        let oldest = calendar.date(byAdding: .day, value: -pendingExpiryDays, to: now) ?? now
        return pending.filter { !acknowledgedIDs.contains($0.id) && $0.date >= oldest }
    }
}

/// いちばん新しい体重と、それがまだ送信待ちか
nonisolated struct LatestWeight: Equatable, Sendable {
    var weightKg: Double
    var date: Date
    /// Watch で記録して、まだ iPhone に届いていない
    var isPending: Bool
}
