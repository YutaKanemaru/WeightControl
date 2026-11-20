import SwiftUI
import SwiftData

/// 初回だけ表示する「はじめに」の画面。
///
/// 1 ページ目でプロフィール、2 ページ目で目標を入力します。目標はあとから決めてもかまいません。
/// `NavigationStack(path:)` は「いま何ページ目まで進んでいるか」を配列で管理する仕組みで、
/// 配列に要素を足すと次のページへ進みます。
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    /// いちばん新しい体重（目標の「スタート時の体重」として残すため）
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    /// 進むページの種類（いまは目標ページだけ）
    private enum Page: Hashable {
        case goal
    }

    @State private var path: [Page] = []
    @State private var profileDraft = ProfileDraft()
    @State private var goalDraft = GoalDraft()
    @State private var heightErrorMessage: String?
    @State private var targetWeightErrorMessage: String?
    @State private var deadlineErrorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ようこそ！")
                            .font(.title2.bold())
                        Text("あなたに合ったカロリーの目安や予測を出すために、いくつか教えてください。入力した情報はこの iPhone の中だけに保存されます。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ProfileFormSections(draft: $profileDraft, heightErrorMessage: heightErrorMessage)

                Section {
                } footer: {
                    Text("このアプリは医療アドバイスではありません。体調に不安があるときは医師に相談してください。ご利用は自己責任でお願いします。")
                }
            }
            .navigationTitle("はじめに")
            .safeAreaInset(edge: .bottom) {
                bottomButton("次へ") {
                    if validatedHeightCm() != nil {
                        path.append(.goal)
                    }
                }
            }
            .onChange(of: profileDraft.heightText) { heightErrorMessage = nil }
            .navigationDestination(for: Page.self) { _ in
                goalPage
            }
        }
    }

    /// 2 ページ目：目標の入力
    private var goalPage: some View {
        Form {
            GoalFormSections(
                draft: $goalDraft,
                currentWeightKg: entries.first?.weightKg,
                targetWeightErrorMessage: targetWeightErrorMessage,
                deadlineErrorMessage: deadlineErrorMessage
            )

            Section {
                Button("目標はあとで決める") {
                    finish(includingGoal: false)
                }
            }
        }
        .navigationTitle("目標")
        .safeAreaInset(edge: .bottom) {
            bottomButton("はじめる") {
                finish(includingGoal: true)
            }
        }
        .onChange(of: goalDraft.targetWeightText) { targetWeightErrorMessage = nil }
        .onChange(of: goalDraft.deadline) { deadlineErrorMessage = nil }
    }

    /// 画面下に固定する大きなボタン
    private func bottomButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
    }

    /// 身長をチェックし、OK なら cm の値を返す（だめならエラー表示をして nil）
    private func validatedHeightCm() -> Double? {
        switch ProfileInputValidator.parseHeightCm(profileDraft.heightText) {
        case .success(let heightCm):
            return heightCm
        case .failure(let error):
            heightErrorMessage = error.message
            return nil
        }
    }

    /// 入力を保存して初回設定を終える。保存すると `RootView` が自動でタブ画面に切り替える。
    private func finish(includingGoal: Bool) {
        guard let heightCm = validatedHeightCm() else {
            // 1 ページ目に戻ってエラーを見せる
            path.removeAll()
            return
        }

        var goal: WeightGoal?
        if includingGoal {
            let targetResult = WeightInputParser.parse(goalDraft.targetWeightText)
            let deadlineResult = ProfileInputValidator.validateDeadline(goalDraft.deadline, today: .now)

            switch (targetResult, deadlineResult) {
            case (.success(let targetWeightKg), .success(let deadline)):
                goal = WeightGoal(
                    targetWeightKg: targetWeightKg,
                    deadline: deadline,
                    startWeightKg: entries.first?.weightKg
                )
            default:
                if case .failure(let error) = targetResult { targetWeightErrorMessage = error.goalMessage }
                if case .failure(let error) = deadlineResult { deadlineErrorMessage = error.message }
                return
            }
        }

        modelContext.insert(UserProfile(
            heightCm: heightCm,
            birthYear: profileDraft.birthYear,
            sex: profileDraft.sex,
            activityLevel: profileDraft.activityLevel
        ))
        if let goal {
            modelContext.insert(goal)
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(.preview(includesProfile: false))
}
