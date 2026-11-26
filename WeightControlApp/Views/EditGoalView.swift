import SwiftUI
import SwiftData

/// 設定画面（とホームの修正案）から開く、目標の編集画面。目標がまだなければ新しく作ります。
///
/// 期限の提案（ゆるやか／ハード）や、自分で決めた期限が無理のないペースかを、その場で `GoalFormSections` がお知らせします。
/// 計算には、ホームと同じ「いまの体重の目安」（直近 3 週間の直線の今日の値）と、ホームと同じ消費カロリーの目安を使います。
/// 開いたときは保存した期限をそのまま出し、目標体重かペースを変えたときだけ今日から計算し直します。
struct EditGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    /// 身長を BMI の目安に使うため
    @Query private var profiles: [UserProfile]
    /// 消費カロリーの目安にヘルスケアの運動量を使うため（プレビューなどで渡されていないときは nil）
    @Environment(HealthSyncController.self) private var health: HealthSyncController?

    /// 編集する目標。nil のときは新しく作る。
    let goal: WeightGoal?
    /// いまの体重（いちばん新しい記録）。目標の「スタート時の体重」として残す。記録がなければ nil。
    let currentWeightKg: Double?

    @State private var draft: GoalDraft
    @State private var targetWeightErrorMessage: String?
    @State private var deadlineErrorMessage: String?
    @State private var isConfirmingDelete = false

    init(goal: WeightGoal?, currentWeightKg: Double?) {
        self.goal = goal
        self.currentWeightKg = currentWeightKg
        // `goal.map(GoalDraft.init(goal:))` と書くと、メインスレッド専用の init を
        // 「どのスレッドからでも呼べる関数」として渡すことになり警告が出るため、クロージャ { } で包んで呼ぶ
        _draft = State(initialValue: goal.map { GoalDraft(goal: $0) } ?? GoalDraft())
    }

    var body: some View {
        Form {
            GoalFormSections(
                draft: $draft,
                currentWeightKg: paceReferenceWeightKg,
                targetWeightErrorMessage: targetWeightErrorMessage,
                deadlineErrorMessage: deadlineErrorMessage,
                heightCm: profiles.first?.heightCm,
                energy: deadlineEnergy
            )

            if goal != nil {
                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("目標を削除", systemImage: "trash")
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
        .onChange(of: draft.mode) { deadlineErrorMessage = nil }
    }

    /// 期限の提案に使うカロリーの目安（ホームと同じ計算）。プロフィールか体重がなければ nil。
    private var deadlineEnergy: DeadlineEnergy? {
        guard let profile = profiles.first, let weightKg = paceReferenceWeightKg else { return nil }
        return GoalDeadlineProposer.energy(
            profile: profile.dashboardProfile,
            weightKg: weightKg,
            healthActivity: health?.activitySummary,
            now: .now
        )
    }

    /// ペースの判定に使う体重：ホームと同じ「いまの体重の目安」。記録が少なくて出せなければ最新の記録。
    private var paceReferenceWeightKg: Double? {
        let points = entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) }
        return HomeDashboardBuilder.currentWeightEstimate(points: points) ?? currentWeightKg
    }

    private func save() {
        let targetResult = WeightInputParser.parse(draft.targetWeightText)
        // ゆるやか／ハードなら提案の期限、自分で決めるなら選んだ日付
        let resolvedDeadline = draft.resolvedDeadline(currentWeightKg: paceReferenceWeightKg, energy: deadlineEnergy)
        let deadlineResult = resolvedDeadline.map { ProfileInputValidator.validateDeadline($0, today: .now) }

        guard case .success(let targetWeightKg) = targetResult,
              case .success(let deadline)? = deadlineResult else {
            if case .failure(let error) = targetResult { targetWeightErrorMessage = error.goalMessage }
            if case .failure(let error)? = deadlineResult { deadlineErrorMessage = error.message }
            // 目標体重は入っているのに、提案を出せなかったとき（体重の記録がない・もう届いているなど）
            if deadlineResult == nil, (try? targetResult.get()) != nil {
                deadlineErrorMessage = ProfileInputValidator.DeadlineError.proposalUnavailableMessage
            }
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
            goal.paceMode = draft.mode
            // 新しい目標を決めたので、キープモードは終える（docs/MAINTENANCE_MODE.md）
            goal.endMaintenance()
        } else {
            modelContext.insert(WeightGoal(
                targetWeightKg: targetWeightKg,
                deadline: deadline,
                startWeightKg: currentWeightKg,
                paceModeRawValue: draft.mode.rawValue
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

#Preview("変更する・大きい文字・ダークモード") {
    let goal = WeightGoal(targetWeightKg: 62.0, deadline: .now.addingTimeInterval(90 * 86_400), startWeightKg: 65.0)
    NavigationStack {
        EditGoalView(goal: goal, currentWeightKg: 64.5)
    }
    .modelContainer(.preview(includesGoal: false))
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}
