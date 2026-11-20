import SwiftUI
import SwiftData

/// 初回だけ表示する「はじめに」の画面。
///
/// 3 つのページで進みます。
/// 1. ようこそ：アプリでできることと、ご利用の前の注意（医療アドバイスではありません など）
/// 2. あなたについて：身長・生まれた年・性別・活動量と、いまの体重（任意）
/// 3. 目標：目標体重と期限（あとから決めてもよい）
///
/// `NavigationStack(path:)` は「いま何ページ目まで進んでいるか」を配列で管理する仕組みで、
/// 配列に要素を足すと次のページへ進み、戻るボタンで要素が減ります。
/// 入力した値は最後に「はじめる」を押すまで保存しないので、途中でアプリを閉じても中途半端なデータは残りません。
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    /// いちばん新しい体重（ヘルスケアなどから先に入っていれば、目標の「スタート時の体重」に使う）
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    /// 進むページの種類
    private enum Page: Hashable {
        case profile
        case goal
    }

    @State private var path: [Page] = []
    @State private var profileDraft = ProfileDraft()
    @State private var currentWeightText = ""
    @State private var goalDraft = GoalDraft()
    @State private var heightErrorMessage: String?
    @State private var currentWeightErrorMessage: String?
    @State private var targetWeightErrorMessage: String?
    @State private var deadlineErrorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            welcomePage
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .profile: profilePage
                    case .goal: goalPage
                    }
                }
        }
    }

    // MARK: - 1 ページ目：ようこそ

    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("ようこそ")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("毎日の体重の記録を、無理なく続けるためのアプリです。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 20) {
                    InfoPointRow(
                        title: "記録はかんたん",
                        detail: "体重を入れるだけ。グラフで変化がひと目で分かります。",
                        systemImage: "scalemass"
                    )
                    InfoPointRow(
                        title: "目標に届く日を予測",
                        detail: "これまでの記録から、いつごろ目標に届きそうかと、1 日の食事の目安をお知らせします。",
                        systemImage: "flag.checkered"
                    )
                    InfoPointRow(
                        title: "続けたことをほめます",
                        detail: "記録した日にはカレンダーにスタンプ。小さな積み重ねを一緒に喜びます。",
                        systemImage: "hands.clap"
                    )
                }

                DashboardCard(title: "ご利用の前に", systemImage: "info.circle") {
                    DisclaimerPoints()
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                bottomButton("確認して次へ") {
                    path.append(.profile)
                }
                Text("「確認して次へ」を押すと、上の内容に同意したものとします。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(.bar)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - 2 ページ目：あなたについて

    private var profilePage: some View {
        Form {
            Section {
            } header: {
                stepHeader(step: 1, message: "カロリーの目安や予測を、あなたに合わせて出すために使います。")
            }

            ProfileFormSections(draft: $profileDraft, heightErrorMessage: heightErrorMessage)

            Section {
                HStack {
                    TextField("いまの体重", text: $currentWeightText, prompt: Text(verbatim: "65.0"))
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    Text(verbatim: "kg")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("いまの体重（任意）")
            } footer: {
                if let currentWeightErrorMessage {
                    FieldErrorText(currentWeightErrorMessage)
                } else {
                    Text("入れておくと、今日の記録として保存し、次の目標の画面でペースの目安を出せます。あとで記録してもかまいません。")
                }
            }
        }
        .navigationTitle("あなたについて")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomButton("次へ") {
                let isHeightValid = validatedHeightCm() != nil
                let isWeightValid = validatedCurrentWeight() != nil
                if isHeightValid && isWeightValid {
                    path.append(.goal)
                }
            }
            .padding()
            .background(.bar)
        }
        .onChange(of: profileDraft.heightText) { heightErrorMessage = nil }
        .onChange(of: currentWeightText) { currentWeightErrorMessage = nil }
    }

    // MARK: - 3 ページ目：目標

    private var goalPage: some View {
        Form {
            Section {
            } header: {
                stepHeader(step: 2, message: "目標は、あとから設定タブでいつでも変えられます。")
            }

            GoalFormSections(
                draft: $goalDraft,
                currentWeightKg: referenceWeightKg,
                targetWeightErrorMessage: targetWeightErrorMessage,
                deadlineErrorMessage: deadlineErrorMessage
            )

            Section {
                Button("目標はあとで決める") {
                    finish(includingGoal: false)
                }
            } footer: {
                Text("目標がなくても、記録・グラフ・カレンダーは使えます。")
            }
        }
        .navigationTitle("目標")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomButton("はじめる") {
                finish(includingGoal: true)
            }
            .padding()
            .background(.bar)
        }
        .onChange(of: goalDraft.targetWeightText) { targetWeightErrorMessage = nil }
        .onChange(of: goalDraft.deadline) { deadlineErrorMessage = nil }
    }

    // MARK: - 部品

    /// 「ステップ 1 / 2」と、そのページで入力する理由
    private func stepHeader(step: Int, message: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ステップ \(step) / 2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }

    /// 画面下に固定する大きなボタン
    private func bottomButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - 入力のチェックと保存

    /// 目標のペースの判定に使う体重：ここで入れた体重、なければすでにある記録
    private var referenceWeightKg: Double? {
        if case .success(let weightKg) = WeightInputParser.parse(currentWeightText) {
            return weightKg
        }
        return entries.first?.weightKg
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

    /// いまの体重をチェックする。
    /// 空欄なら「入れない」で OK（`.some(nil)`）、数字なら `.some(kg)`、おかしければエラー表示をして `nil`。
    private func validatedCurrentWeight() -> Double?? {
        switch WeightInputParser.parse(currentWeightText) {
        case .success(let weightKg):
            return .some(weightKg)
        case .failure(.empty):
            return .some(nil)
        case .failure(let error):
            currentWeightErrorMessage = error.currentWeightMessage
            return nil
        }
    }

    /// 入力を保存して初回設定を終える。保存すると `RootView` が自動でタブ画面に切り替える。
    private func finish(includingGoal: Bool) {
        guard let heightCm = validatedHeightCm(), let currentWeight = validatedCurrentWeight() else {
            // 2 ページ目に戻ってエラーを見せる
            path = [.profile]
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
                    startWeightKg: currentWeight ?? entries.first?.weightKg
                )
            default:
                if case .failure(let error) = targetResult { targetWeightErrorMessage = error.goalMessage }
                if case .failure(let error) = deadlineResult { deadlineErrorMessage = error.message }
                return
            }
        }

        if let currentWeight {
            modelContext.insert(WeightEntry(date: .now, weightKg: currentWeight))
        }
        if let goal {
            modelContext.insert(goal)
        }
        // プロフィールを最後に保存する（保存した瞬間に画面が切り替わるため）
        modelContext.insert(UserProfile(
            heightCm: heightCm,
            birthYear: profileDraft.birthYear,
            sex: profileDraft.sex,
            activityLevel: profileDraft.activityLevel
        ))
    }
}

extension WeightInputParser.ParseError {
    /// 初回設定の「いまの体重」の欄に出すエラーメッセージ（空欄はエラーにしない）
    fileprivate var currentWeightMessage: String {
        switch self {
        case .empty, .notANumber: String(localized: "数字で入力してください（例: 65.0）。")
        case .outOfRange: String(localized: "20〜300 kg の範囲で入力してください。")
        }
    }
}

#Preview("はじめに") {
    OnboardingView()
        .modelContainer(.preview(includesProfile: false))
}

#Preview("大きい文字・ダークモード") {
    OnboardingView()
        .modelContainer(.preview(includesProfile: false))
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
}
