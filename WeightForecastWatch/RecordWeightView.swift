import SwiftUI

/// Watch で体重を記録する画面。仕様は docs/WATCH.md。
///
/// - 前回の体重から始まるので、毎日の記録は Digital Crown（横の回るつまみ）を少し回して「記録する」を押すだけで済みます。
///   Digital Crown は 1 目盛り 0.1 kg。「−」「＋」ボタンでも動かせます。
/// - 前回と 2.0 kg 以上ちがうときは、打ち間違い（回しすぎ）かもしれないので確認します（iPhone の入力画面と同じ）。
/// - 記録したら軽い手ごたえ（触覚）を返して、ほめる一言を出します。
struct RecordWeightView: View {
    @Environment(PhoneConnection.self) private var connection
    @Environment(\.dismiss) private var dismiss

    /// 前回の体重（確認に使う）。記録がなければ nil。
    let previousKg: Double?

    /// Digital Crown で動かす値。小さな誤差が出るので、表示と保存は `WatchDisplay.rounded` で丸める
    @State private var crownValue: Double
    /// 前回と大きくちがうときの差（kg）。nil なら確認を出さない
    @State private var largeChangeKg: Double?
    @State private var didRecord = false

    init(startKg: Double, previousKg: Double?) {
        self.previousKg = previousKg
        _crownValue = State(initialValue: startKg)
    }

    private var weightKg: Double { WatchDisplay.rounded(crownValue) }

    var body: some View {
        Group {
            if didRecord {
                RecordedView()
            } else {
                entry
            }
        }
        .sensoryFeedback(.success, trigger: didRecord) { _, new in new }
    }

    private var entry: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                StepButton(systemImage: "minus", label: "0.1 kg 減らす") { step(-1) }
                VStack(spacing: 0) {
                    Text(WatchSummary.kg(weightKg))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: weightKg))
                    Text("kg")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .focusable()
                .digitalCrownRotation(
                    $crownValue,
                    from: WatchDisplay.validRangeKg.lowerBound,
                    through: WatchDisplay.validRangeKg.upperBound,
                    by: WatchDisplay.stepKg,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("体重")
                .accessibilityValue("\(WatchSummary.kg(weightKg)) kg")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(1)
                    case .decrement: step(-1)
                    @unknown default: break
                    }
                }
                StepButton(systemImage: "plus", label: "0.1 kg 増やす") { step(1) }
            }
            Text("Digital Crown で合わせる")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(action: save) {
                Text("記録する")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("体重を記録")
        .alert(
            "前回と \(WatchSummary.kg(abs(largeChangeKg ?? 0))) kg ちがいます",
            isPresented: Binding(get: { largeChangeKg != nil }, set: { if !$0 { largeChangeKg = nil } })
        ) {
            Button("このまま記録する") { record() }
            Button("直す", role: .cancel) {}
        } message: {
            Text("数字が合っているか確かめてください。")
        }
    }

    private func step(_ steps: Int) {
        crownValue = WatchDisplay.rounded(weightKg + Double(steps) * WatchDisplay.stepKg)
    }

    private func save() {
        if let diff = WatchDisplay.largeChange(newKg: weightKg, previousKg: previousKg) {
            largeChangeKg = diff
            return
        }
        record()
    }

    private func record() {
        connection.record(weightKg: weightKg)
        didRecord = true
        // ほめる一言を少し見せてから、最初の画面に戻る
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }
}

/// 「−」「＋」の丸いボタン
private struct StepButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(width: 36)
        .accessibilityLabel(label)
    }
}

/// 記録したあとに出す、ほめる一言
private struct RecordedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("記録しました")
                .font(.headline)
            Text("今日も記録できました。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        RecordWeightView(startKg: 64.2, previousKg: 64.2)
    }
    .environment(PhoneConnection())
}
