import SwiftUI

/// 目標の入力欄に入っている「編集中の値」。
struct GoalDraft {
    var targetWeightText = ""
    /// 期限。はじめは「今日から 3 か月後」にしておく
    var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now

    init() {}

    /// 保存済みの目標から、編集の出発点を作る
    init(goal: WeightGoal) {
        targetWeightText = goal.targetWeightKg.formatted(.number.precision(.fractionLength(1)).grouping(.never))
        deadline = goal.deadline
    }
}

/// 目標の入力欄（目標体重・期限）と、入力中の目標が無理のないペースかのひとこと、目標体重の BMI の目安。
/// 初回設定・設定画面・ホームの修正案から開く画面で使う部品です。
///
/// ペースの判定は Logic の `GoalPlanAdvisor`（中身は `GoalSafetyChecker`）に任せ、
/// ここでは結果に合わせて文言と色、修正案のボタンを出し分けるだけにしています。
struct GoalFormSections: View {
    @Binding var draft: GoalDraft
    /// いまの体重の目安（kg）。ペースの判定に使う。記録がなければ nil。
    let currentWeightKg: Double?
    let targetWeightErrorMessage: String?
    let deadlineErrorMessage: String?
    /// 身長（cm）。BMI の目安を出すのに使う。分からなければ nil（BMI の欄を出さない）。
    var heightCm: Double? = nil

    /// 期限として選べるいちばん早い日（明日）
    private var tomorrow: Date {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? .now
    }

    var body: some View {
        Section {
            HStack {
                TextField("目標体重", text: $draft.targetWeightText, prompt: Text(placeholder))
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
                    .accessibilityLabel(Text("目標体重（キログラム）"))
                Text(verbatim: "kg")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } header: {
            Text("目標体重")
        } footer: {
            if let targetWeightErrorMessage {
                FieldErrorText(targetWeightErrorMessage)
            } else if let currentWeightKg {
                Text("いまの体重の目安は \(currentWeightKg, format: .number.precision(.fractionLength(1))) kg です。")
            }
        }

        Section {
            DatePicker(selection: $draft.deadline, in: tomorrow..., displayedComponents: .date) {
                Label("期限", systemImage: "calendar.badge.clock")
            }
        } header: {
            Text("いつまでに")
        } footer: {
            if let deadlineErrorMessage {
                FieldErrorText(deadlineErrorMessage)
            }
        }

        paceSection

        if let bmiAdvice {
            GoalBMISection(advice: bmiAdvice, draft: $draft)
        }
    }

    // MARK: - BMI の目安

    private var bmiAdvice: GoalBMIAdvice? {
        GoalBMIAdvisor.advice(
            targetWeightKg: try? WeightInputParser.parse(draft.targetWeightText).get(),
            currentWeightKg: currentWeightKg,
            heightCm: heightCm
        )
    }

    // MARK: - ペースのひとこと

    private var advice: GoalPlanAdvice {
        let targetWeightKg = try? WeightInputParser.parse(draft.targetWeightText).get()
        return GoalPlanAdvisor.advice(
            targetWeightKg: targetWeightKg,
            currentWeightKg: currentWeightKg,
            deadline: draft.deadline,
            now: .now
        )
    }

    @ViewBuilder
    private var paceSection: some View {
        switch advice {
        case .needsTargetWeight:
            EmptyView()
        case .needsCurrentWeight:
            Section("ペースの目安") {
                NoticeLabel("体重を記録すると、無理のないペースかどうかをお知らせします。")
            }
        case .alreadyAtGoal:
            Section("ペースの目安") {
                NoticeLabel("いまの体重は、もう目標とほぼ同じです。この体重をキープしていきましょう。", style: .success)
            }
        case .comfortable(let weeklyChangeKg, let daysLeft):
            Section {
                NoticeLabel(text: Text("無理のないペースです。1 週間に \(abs(weeklyChangeKg), format: .number.precision(.fractionLength(1))) kg ずつ、あと \(daysLeft) 日です。"), style: .success)
            } header: {
                Text("ペースの目安")
            } footer: {
                Text("減らすときは 1 週間に体重の 1 %、増やすときは 0.5 % までを目安にしています。医療的な判断ではありません。")
            }
        case .tooFast(let correction):
            Section {
                NoticeLabel(text: tooFastMessage(correction), style: .caution)
                Button {
                    draft.deadline = correction.suggestedDeadline
                } label: {
                    Label {
                        Text("期限を \(Text(correction.suggestedDeadline, format: .dateTime.year().month().day())) にする")
                    } icon: {
                        Image(systemName: "calendar.badge.plus")
                    }
                }
                if let suggestedKg = correction.suggestedGoalWeightKg {
                    Button {
                        draft.targetWeightText = suggestedKg.formatted(.number.precision(.fractionLength(1)).grouping(.never))
                    } label: {
                        Label {
                            Text("目標体重を \(suggestedKg, format: .number.precision(.fractionLength(1))) kg にする")
                        } icon: {
                            Image(systemName: "scalemass")
                        }
                    }
                }
            } header: {
                Text("ペースの目安")
            } footer: {
                Text("ゆっくりのほうが、リバウンドしにくく続けやすくなります。このままの目標で保存することもできます。医療的な判断ではありません。")
            }
        }
    }

    private func tooFastMessage(_ correction: GoalCorrection) -> Text {
        if let required = correction.requiredWeeklyChangeKg {
            Text("少し速めのペースです（1 週間に \(abs(required), format: .number.precision(.fractionLength(1))) kg）。無理のない目安は \(abs(correction.maxWeeklyChangeKg), format: .number.precision(.fractionLength(1))) kg までです。")
        } else {
            Text("少し速めのペースです。")
        }
    }

    /// 入力欄のうすい見本。いまの体重があれば、その 1 kg 下を見せる。
    private var placeholder: String {
        let example = (currentWeightKg ?? 61) - 1
        return example.formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }
}

extension WeightInputParser.ParseError {
    /// 目標体重の欄に出すエラーメッセージ
    var goalMessage: String {
        switch self {
        case .empty: String(localized: "目標体重を入力してください。")
        case .notANumber: String(localized: "数字で入力してください（例: 60.0）。")
        case .outOfRange: String(localized: "20〜300 kg の範囲で入力してください。")
        }
    }
}

extension ProfileInputValidator.DeadlineError {
    /// 期限の欄に出すエラーメッセージ
    var message: String {
        switch self {
        case .notInFuture: String(localized: "期限は明日以降の日付を選んでください。")
        }
    }
}

#Preview("無理のないペース") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(draft: $draft, currentWeightKg: 64.5, targetWeightErrorMessage: nil, deadlineErrorMessage: nil, heightCm: 160)
        }
    }
    .onAppear { draft.targetWeightText = "62.0" }
}

#Preview("速すぎる・大きい文字・ダークモード") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(draft: $draft, currentWeightKg: 64.5, targetWeightErrorMessage: nil, deadlineErrorMessage: nil, heightCm: 160)
        }
    }
    .onAppear { draft.targetWeightText = "50.0" }
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}

#Preview("記録なし") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(draft: $draft, currentWeightKg: nil, targetWeightErrorMessage: nil, deadlineErrorMessage: nil)
        }
    }
    .onAppear { draft.targetWeightText = "60.0" }
}
