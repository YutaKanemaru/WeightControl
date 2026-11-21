import SwiftUI

/// 目標の入力欄の「BMI の目安」。`GoalFormSections` の中で使います。
///
/// 判定は Logic の `GoalBMIAdvisor` に任せ、ここでは結果に合わせて文言・色・直すボタンを出し分けるだけです。
/// どの判定でも保存はできます（止めずに、理由と直し方を見せる方針。docs/BMI_GOAL.md）。
struct GoalBMISection: View {
    let advice: GoalBMIAdvice
    /// 「目標を ◯ kg にする」ボタンで、目標体重の欄を書き換えるため
    @Binding var draft: GoalDraft

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                MetricView("目標の BMI", value: advice.goalBMI, caption: Text(advice.goalBand.label), size: .medium, tint: advice.goalBand.tint)
                if let currentBMI = advice.currentBMI {
                    MetricView("いまの BMI", value: currentBMI, size: .medium)
                }
            }

            LabeledContent {
                Text("\(advice.normalRangeKg.lowerBound, format: kgFormat)〜\(advice.normalRangeKg.upperBound, format: kgFormat) kg")
                    .monospacedDigit()
            } label: {
                Text("ふつうの範囲（BMI 18.5〜25 未満）")
            }
            LabeledContent {
                Text("\(advice.standardWeightKg, format: kgFormat) kg")
                    .monospacedDigit()
            } label: {
                Text("標準体重（BMI 22）")
            }

            verdictRows
        } header: {
            Text("BMI の目安")
        } footer: {
            Text("BMI ＝ 体重 ÷ 身長(m) ÷ 身長(m)。大人向けの目安で、筋肉の多い方は高めに出ます。18 歳未満の方、妊娠中・授乳中の方、治療中の病気がある方は、目標を医師に相談してください。医療的な判断ではありません。")
        }
    }

    @ViewBuilder
    private var verdictRows: some View {
        switch advice.verdict {
        case .normal:
            NoticeLabel("ふつうの範囲の目標です。", style: .success)

        case .belowNormal(let suggestedKg):
            NoticeLabel(text: Text("目標体重の BMI が 18.5 を下回っています。やせすぎは体の負担になることがあるので、\(suggestedKg, format: kgFormat) kg（BMI 18.5）以上を目安にしてみませんか。"), style: .caution)
            setTargetButton(kg: suggestedKg, title: Text("目標体重を \(suggestedKg, format: kgFormat) kg にする"))

        case .gainingTowardNormal(let minimumKg):
            NoticeLabel(text: Text("体重を増やしていく、よい目標です。BMI 18.5（\(minimumKg, format: kgFormat) kg）以上が、ふつうの範囲の目安です。"))

        case .firstStep(let fivePercentKg, let tenPercentKg, let firstStepKg):
            NoticeLabel(text: Text("最初の一歩にぴったりの目標です。まずは今の体重の 5〜10 %（\(fivePercentKg, format: kgFormat)〜\(tenPercentKg, format: kgFormat) kg）を中間の目安にして、届いたら次の目標を決めていきましょう。"), style: .success)
            if let firstStepKg {
                setTargetButton(kg: firstStepKg, title: Text("まず \(firstStepKg, format: kgFormat) kg（5 % 減）を目標にする"))
            }

        case .aboveNormal(let maximumKg, let isGaining):
            if isGaining {
                NoticeLabel(text: Text("目標体重の BMI が 25 以上になります。増やしすぎに気をつけて、\(maximumKg, format: kgFormat) kg までを目安にしてみませんか。"), style: .caution)
                setTargetButton(kg: maximumKg, title: Text("目標体重を \(maximumKg, format: kgFormat) kg にする"))
            } else {
                NoticeLabel(text: Text("目標体重の BMI は 25 以上です。ふつうの範囲は \(maximumKg, format: kgFormat) kg までが目安です。"), style: .caution)
            }
        }
    }

    private func setTargetButton(kg: Double, title: Text) -> some View {
        Button {
            draft.targetWeightText = kg.formatted(.number.precision(.fractionLength(1)).grouping(.never))
        } label: {
            Label {
                title
            } icon: {
                Image(systemName: "scalemass")
            }
        }
    }

    private var kgFormat: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(1))
    }
}

extension BMIBand {
    /// 画面での呼び方。学会の「低体重・肥満」は責める感じがするので使わない。
    var label: LocalizedStringKey {
        switch self {
        case .low: "低め"
        case .normal: "ふつう"
        case .high: "高め"
        }
    }

    /// 数字の色：ふつうは標準の色、外れたら注意のオレンジ
    var tint: Color {
        switch self {
        case .normal: .primary
        case .low, .high: .orange
        }
    }
}

#Preview("ふつう・低め・高めから減らす・高めへ増やす") {
    @Previewable @State var draft = GoalDraft()
    let cases: [(Double, Double?)] = [(56, 60), (45, 52), (70, 80), (66, 60)]
    NavigationStack {
        Form {
            ForEach(cases.indices, id: \.self) { index in
                if let advice = GoalBMIAdvisor.advice(targetWeightKg: cases[index].0, currentWeightKg: cases[index].1, heightCm: 160) {
                    GoalBMISection(advice: advice, draft: $draft)
                }
            }
        }
    }
}

#Preview("大きい文字・ダークモード") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            if let advice = GoalBMIAdvisor.advice(targetWeightKg: 45, currentWeightKg: 52, heightCm: 160) {
                GoalBMISection(advice: advice, draft: $draft)
            }
        }
    }
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}
