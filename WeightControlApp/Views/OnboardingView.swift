import SwiftUI
import SwiftData

/// 初回だけ表示する「はじめに」の画面。
///
/// 次のページで進みます。
/// 1. ようこそ：アプリでできることと、ご利用の前の注意（医療アドバイスではありません など）
/// 2. ヘルスケア：連携するかを選ぶ。連携すると、ヘルスケアの身長・生まれた年・性別を次のページに入れておき、
///    体重の記録も取り込む（ヘルスケアを使えない端末や、もう連携している場合はこのページを飛ばす）
/// 3. あなたについて：身長・生まれた年・性別・活動量と、いまの体重（任意）
/// 4. 目標：目標体重と期限（あとから決めてもよい）
///
/// `NavigationStack(path:)` は「いま何ページ目まで進んでいるか」を配列で管理する仕組みで、
/// 配列に要素を足すと次のページへ進み、戻るボタンで要素が減ります。
/// 入力した値は最後に「はじめる」を押すまで保存しないので、途中でアプリを閉じても中途半端なデータは残りません。
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    /// ヘルスケア連携の係（プレビューなどで渡されていないときは nil）
    @Environment(HealthSyncController.self) private var health: HealthSyncController?
    /// いちばん新しい体重（ヘルスケアなどから先に入っていれば、目標の「スタート時の体重」に使う）
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    /// 進むページの種類
    private enum Page: Hashable {
        case health
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
    /// ヘルスケアの許可と取り込みを待っている間 true
    @State private var isConnectingHealth = false
    /// ヘルスケアから入力欄に入れた項目があるか（「入れておきました」のお知らせを出す）
    @State private var didPrefillFromHealth = false
    /// ヘルスケアのページで「連携する」か「今は連携しない」を選び終えたか
    /// （連携した後もステップの数が変わらないように覚えておく）
    @State private var didFinishHealthStep = false

    var body: some View {
        NavigationStack(path: $path) {
            welcomePage
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .health: healthPage
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
                    path.append(showsHealthPage ? .health : .profile)
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

    // MARK: - ヘルスケア（使える端末だけ）

    /// ヘルスケアのページを出すか（ヘルスケアを使えない端末と、すでに連携済みなら出さない）
    private var showsHealthPage: Bool {
        guard let health else { return false }
        return health.isAvailable && (!health.isEnabled || isConnectingHealth || didFinishHealthStep)
    }

    /// 入力のページが全部で何ステップあるか
    private var totalSteps: Int { showsHealthPage ? 3 : 2 }

    private var healthPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    stepHeader(step: 1, message: "あとから設定タブでいつでも変えられます。")
                    Text("ヘルスケアと連携しますか？")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(alignment: .leading, spacing: 20) {
                    InfoPointRow(
                        title: "身長などを引き継ぎ",
                        detail: "ヘルスケアに登録している身長・生年月日・性別を、次のページに入れておきます。",
                        systemImage: "person.text.rectangle"
                    )
                    InfoPointRow(
                        title: "体重の記録を取り込み",
                        detail: "体重計アプリなどでヘルスケアに記録した体重も、グラフや予測に使えます。",
                        systemImage: "scalemass"
                    )
                    InfoPointRow(
                        title: "運動した日にスタンプ",
                        detail: "歩数やワークアウトから、運動した日のカレンダーに自動でスタンプを押します。",
                        systemImage: "figure.run"
                    )
                }

                NoticeLabel("「連携する」を押すと、どのデータを読み取るかを選ぶ画面が出ます。データはこの iPhone の中だけで使い、外部には送りません。")
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: connectHealth) {
                    HStack(spacing: 8) {
                        if isConnectingHealth {
                            ProgressView()
                        }
                        (isConnectingHealth ? Text("読み込み中…") : Text("連携する"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    didFinishHealthStep = true
                    path.append(.profile)
                } label: {
                    Text("今は連携しない")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .disabled(isConnectingHealth)
            .padding()
            .background(.bar)
        }
        .navigationTitle("ヘルスケア")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// ヘルスケアの許可を求め、体重を取り込み、身長などを入力欄に入れてから次のページへ進む
    private func connectHealth() {
        guard let health else { return }
        isConnectingHealth = true
        Task {
            await health.enable(context: modelContext)
            apply(await health.profilePrefill())
            didFinishHealthStep = true
            isConnectingHealth = false
            path.append(.profile)
        }
    }

    /// ヘルスケアの値を入力欄に入れる（ない項目は触らない）
    private func apply(_ prefill: HealthProfilePrefill) {
        guard !prefill.isEmpty else { return }
        if let heightCm = prefill.heightCm {
            profileDraft.heightText = heightCm.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        }
        if let birthYear = prefill.birthYear {
            profileDraft.birthYear = birthYear
        }
        switch prefill.sex {
        case .male: profileDraft.sex = .male
        case .female: profileDraft.sex = .female
        case nil: break
        }
        didPrefillFromHealth = true
    }

    // MARK: - あなたについて

    private var profilePage: some View {
        Form {
            Section {
            } header: {
                stepHeader(step: totalSteps - 1, message: "カロリーの目安や予測を、あなたに合わせて出すために使います。")
            }

            if didPrefillFromHealth {
                Section {
                    NoticeLabel("ヘルスケアから身長などを入れておきました。違っていれば直してください。", style: .success)
                }
            }

            ProfileFormSections(draft: $profileDraft, heightErrorMessage: heightErrorMessage)

            if let latest = entries.first {
                // ヘルスケアなどから記録がもう入っているときは、入力欄の代わりに最新の体重を見せる
                Section {
                    LabeledContent {
                        Text("\(latest.weightKg, format: .number.precision(.fractionLength(1))) kg")
                            .monospacedDigit()
                    } label: {
                        Label("最新の記録", systemImage: "scalemass")
                    }
                } header: {
                    Text("いまの体重")
                } footer: {
                    Text("ヘルスケアから取り込んだ記録を使います。")
                }
            } else {
                Section {
                    HStack {
                        TextField("いまの体重", text: $currentWeightText, prompt: Text(verbatim: "65.0"))
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit())
                            .accessibilityLabel(Text("いまの体重（キログラム）"))
                        Text(verbatim: "kg")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
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

    // MARK: - 目標

    private var goalPage: some View {
        Form {
            Section {
            } header: {
                stepHeader(step: totalSteps, message: "目標は、あとから設定タブでいつでも変えられます。")
            }

            GoalFormSections(
                draft: $goalDraft,
                currentWeightKg: referenceWeightKg,
                targetWeightErrorMessage: targetWeightErrorMessage,
                deadlineErrorMessage: deadlineErrorMessage,
                heightCm: try? ProfileInputValidator.parseHeightCm(profileDraft.heightText).get()
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
            Text("ステップ \(step) / \(totalSteps)")
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
        .environment(HealthSyncController())
}

#Preview("大きい文字・ダークモード") {
    OnboardingView()
        .modelContainer(.preview(includesProfile: false))
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
}
