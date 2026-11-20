import Foundation

/// 体重の入力画面の「−」「＋」ボタン（0.1 kg ずつ増減）と、入力欄の初期値の文字を作るロジック。
///
/// 毎日の体重は前回と少ししか違わないので、前回の体重を入れておき、
/// ボタンで少しだけ動かして保存できるようにすると、キーボードを打たずに記録できます。
nonisolated enum WeightEntryStepper {
    /// 1 回押したときに動く量（kg）
    static let stepKg = 0.1

    /// 入力欄に入れる文字（小数第 1 位まで。例: 64.5 → "64.5"）。
    ///
    /// 地域設定に関係なく小数点は「.」にします（`WeightInputParser` は「.」も「,」も読めます）。
    static func text(for weightKg: Double) -> String {
        String(format: "%.1f", (weightKg * 10).rounded() / 10)
    }

    /// 入力欄の文字を `steps` 回分（マイナスなら減らす向き）動かした文字を返します。
    ///
    /// - 入力欄が空や読めない文字のときは、`fallbackKg`（前回の体重）から動かします。前回もなければ動かしません。
    /// - `WeightInputParser.validRangeKg`（20〜300 kg）からはみ出さないように止めます。
    /// - Returns: 新しい入力欄の文字。動かせないときは nil（入力欄はそのまま）。
    static func adjusted(_ text: String, steps: Int, fallbackKg: Double?) -> String? {
        let baseKg: Double
        switch WeightInputParser.parse(text) {
        case .success(let kg):
            baseKg = kg
        case .failure:
            guard let fallbackKg else { return nil }
            baseKg = fallbackKg
        }
        let range = WeightInputParser.validRangeKg
        // 0.1 を何度も足すと小数の誤差がたまるので、0.1 kg 単位の整数で計算する
        let tenths = (baseKg * 10).rounded() + Double(steps)
        let clamped = min(max(tenths / 10, range.lowerBound), range.upperBound)
        return self.text(for: clamped)
    }
}
