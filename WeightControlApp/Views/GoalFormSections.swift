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

/// 目標の入力欄（目標体重・期限）。初回設定と設定画面の両方で使う部品です。
struct GoalFormSections: View {
    @Binding var draft: GoalDraft
    /// いまの体重（いちばん新しい記録）。記録がなければ nil。
    let currentWeightKg: Double?
    let targetWeightErrorMessage: String?
    let deadlineErrorMessage: String?

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
                Text(verbatim: "kg")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("目標体重")
        } footer: {
            if let targetWeightErrorMessage {
                Text(targetWeightErrorMessage)
                    .foregroundStyle(.red)
            } else if let currentWeightKg {
                Text("いまの体重は \(currentWeightKg, format: .number.precision(.fractionLength(1))) kg です。")
            }
        }

        Section {
            DatePicker("期限", selection: $draft.deadline, in: tomorrow..., displayedComponents: .date)
        } header: {
            Text("いつまでに")
        } footer: {
            if let deadlineErrorMessage {
                Text(deadlineErrorMessage)
                    .foregroundStyle(.red)
            } else {
                Text("無理のないペースかどうかは、今後のアップデートでお知らせできるようになります。")
            }
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

#Preview {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(draft: $draft, currentWeightKg: 64.5, targetWeightErrorMessage: nil, deadlineErrorMessage: nil)
        }
    }
}
