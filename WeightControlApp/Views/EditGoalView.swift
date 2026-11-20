import SwiftUI
import SwiftData

/// 設定画面から開く、目標の編集画面。目標がまだなければ新しく作ります。
struct EditGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 編集する目標。nil のときは新しく作る。
    let goal: WeightGoal?
    /// いまの体重（いちばん新しい記録）。記録がなければ nil。
    let currentWeightKg: Double?

    @State private var draft: GoalDraft
    @State private var targetWeightErrorMessage: String?
    @State private var deadlineErrorMessage: String?
    @State private var isConfirmingDelete = false

    init(goal: WeightGoal?, currentWeightKg: Double?) {
        self.goal = goal
        self.currentWeightKg = currentWeightKg
        _draft = State(initialValue: goal.map(GoalDraft.init(goal:)) ?? GoalDraft())
    }

    var body: some View {
        Form {
            GoalFormSections(
                draft: $draft,
                currentWeightKg: currentWeightKg,
                targetWeightErrorMessage: targetWeightErrorMessage,
                deadlineErrorMessage: deadlineErrorMessage
            )

            if goal != nil {
                Section {
                    Button("目標を削除", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .navigationTitle(goal == nil ? "目標を決める" : "目標を変更")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        // 削除はやり直せないので、確認してから消す
        .confirmationDialog("目標を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive, action: deleteGoal)
        } message: {
            Text("体重の記録は消えません。")
        }
        .onChange(of: draft.targetWeightText) { targetWeightErrorMessage = nil }
        .onChange(of: draft.deadline) { deadlineErrorMessage = nil }
    }

    private func save() {
        let targetResult = WeightInputParser.parse(draft.targetWeightText)
        let deadlineResult = ProfileInputValidator.validateDeadline(draft.deadline, today: .now)

        guard case .success(let targetWeightKg) = targetResult,
              case .success(let deadline) = deadlineResult else {
            if case .failure(let error) = targetResult { targetWeightErrorMessage = error.goalMessage }
            if case .failure(let error) = deadlineResult { deadlineErrorMessage = error.message }
            return
        }

        if let goal {
            // 目標体重を変えたときは、そこを新しいスタートとして記録し直す
            if goal.targetWeightKg != targetWeightKg {
                goal.startDate = .now
                goal.startWeightKg = currentWeightKg
            }
            goal.targetWeightKg = targetWeightKg
            goal.deadline = deadline
        } else {
            modelContext.insert(WeightGoal(
                targetWeightKg: targetWeightKg,
                deadline: deadline,
                startWeightKg: currentWeightKg
            ))
        }
        dismiss()
    }

    private func deleteGoal() {
        if let goal {
            modelContext.delete(goal)
        }
        dismiss()
    }
}

#Preview("新しく作る") {
    NavigationStack {
        EditGoalView(goal: nil, currentWeightKg: 64.5)
    }
    .modelContainer(.preview(includesGoal: false))
}
