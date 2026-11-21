import SwiftUI

/// 目標の入力欄に入っている「編集中の値」。
struct GoalDraft {
    /// 目標体重の入力欄。変えたら、保存した期限はやめて今日から計算し直す
    var targetWeightText = "" {
        didSet {
            if targetWeightText != oldValue { keepsSavedDeadline = false }
        }
    }
    /// 期限の決め方。新しく決めるときは「ゆるやか」から
    var mode: GoalPaceMode = .gentle
    /// 「自分で決める」の日付。はじめは「今日から 3 か月後」。保存済みの目標を開いたときは保存した期限
    var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    /// 保存した期限をそのまま出しているか。
    /// 目標の編集画面を開くたびに期限が動かないように、目標体重かモードを変えるまでは保存した期限を使います。
    var keepsSavedDeadline = false

    init() {}

    /// 保存済みの目標から、編集の出発点を作る
    init(goal: WeightGoal) {
        targetWeightText = goal.targetWeightKg.formatted(.number.precision(.fractionLength(1)).grouping(.never))
        mode = goal.paceMode
        deadline = goal.deadline
        keepsSavedDeadline = true
    }

    /// 入力中の目標体重（kg）。数字として読めなければ nil
    var targetWeightKg: Double? {
        try? WeightInputParser.parse(targetWeightText).get()
    }

    /// `mode`（ゆるやか／ハード）で計算した期限の提案。目標体重か今の体重が分からなければ nil。
    func proposal(
        for mode: GoalPaceMode,
        currentWeightKg: Double?,
        energy: DeadlineEnergy?,
        now: Date = .now
    ) -> GoalDeadlineProposal? {
        guard let targetWeightKg, let currentWeightKg else { return nil }
        return GoalDeadlineProposer.propose(
            currentWeightKg: currentWeightKg,
            targetWeightKg: targetWeightKg,
            mode: mode,
            energy: energy,
            now: now
        )
    }

    /// 保存した期限をそのまま使うか（明日以降の日付のときだけ。過ぎていたら計算し直す）
    func usesSavedDeadline(now: Date = .now) -> Bool {
        keepsSavedDeadline && DayMath.days(from: now, to: deadline, calendar: .current) > 0
    }

    /// 保存する期限。ゆるやか／ハードで提案を出せないときは nil。
    func resolvedDeadline(currentWeightKg: Double?, energy: DeadlineEnergy?, now: Date = .now) -> Date? {
        if mode == .manual || usesSavedDeadline(now: now) { return deadline }
        return proposal(for: mode, currentWeightKg: currentWeightKg, energy: energy, now: now)?.deadline
    }
}

/// 目標の入力欄（目標体重・ペース・期限）と、目標体重の BMI の目安。
/// 初回設定・設定画面・ホームの修正案から開く画面で使う部品です。
///
/// - ゆるやか／ハード：期限は `GoalDeadlineProposer` が計算して大きく出します（仕様は docs/GOAL_DEADLINE.md）。
/// - 自分で決める：今までどおり日付を選び、ペースの判定は `GoalPlanAdvisor`（中身は `GoalSafetyChecker`）に任せます。
///
/// ここでは結果に合わせて文言と色、修正案のボタンを出し分けるだけにしています。
struct GoalFormSections: View {
    @Binding var draft: GoalDraft
    /// いまの体重の目安（kg）。期限の提案とペースの判定に使う。記録がなければ nil。
    let currentWeightKg: Double?
    let targetWeightErrorMessage: String?
    let deadlineErrorMessage: String?
    /// 身長（cm）。BMI の目安を出すのに使う。分からなければ nil（BMI の欄を出さない）。
    var heightCm: Double? = nil
    /// カロリーの目安。期限を食事の下限で止めるのに使う。分からなければ nil。
    var energy: DeadlineEnergy? = nil

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

        if let bmiAdvice {
            GoalBMISection(advice: bmiAdvice, draft: $draft)
        }

        modeSection

        if draft.mode == .manual {
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
        } else {
            proposedDeadlineSection
        }
    }

    // MARK: - ペース（期限の決め方）

    private var modeSection: some View {
        Section {
            Picker(selection: modeBinding) {
                ForEach(GoalPaceMode.allCases) { mode in
                    modeRow(mode).tag(mode)
                }
            } label: {
                Text("ペース")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("ペース")
        } footer: {
            Text("ゆるやかとハードは、目標体重からアプリが期限を計算します。")
        }
    }

    /// モードを切り替えたときの決まり：
    /// - 「自分で決める」にしたら、日付の最初の値はそれまで出ていた提案の日付にする
    /// - 保存した期限はやめて、今日から計算し直す
    private var modeBinding: Binding<GoalPaceMode> {
        Binding {
            draft.mode
        } set: { newMode in
            guard newMode != draft.mode else { return }
            if newMode == .manual, let shown = shownDeadline {
                draft.deadline = shown
            }
            draft.keepsSavedDeadline = false
            draft.mode = newMode
        }
    }

    /// いま画面に出ている期限（保存した期限か、提案）
    private var shownDeadline: Date? {
        draft.resolvedDeadline(currentWeightKg: currentWeightKg, energy: energy)
    }

    private func modeRow(_ mode: GoalPaceMode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mode.title)
            Text(modeDetail(mode))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// モードの行の小さな説明。提案を出せるときは、そのペースと期限も見せる。
    private func modeDetail(_ mode: GoalPaceMode) -> Text {
        guard mode != .manual else { return Text("期限の日付を自分で選びます") }
        // 目標体重と今の体重が分からないうちは、減らす前提の割合を見せる
        var isLosing = true
        if let targetWeightKg = draft.targetWeightKg, let currentWeightKg {
            isLosing = targetWeightKg < currentWeightKg
        }
        let percent = (mode.weeklyRatio(isLosing: isLosing) ?? 0) * 100
        let ratioText = Text("1 週間に体重の \(percent, format: .number.precision(.fractionLength(0...2))) %")
        if case .proposed(let suggestion)? = draft.proposal(for: mode, currentWeightKg: currentWeightKg, energy: energy) {
            return Text("\(ratioText)・\(Text(suggestion.deadline, format: dateFormat(suggestion.deadline)))ごろ")
        }
        return ratioText
    }

    // MARK: - 提案した期限

    @ViewBuilder
    private var proposedDeadlineSection: some View {
        Section {
            if draft.usesSavedDeadline() {
                savedDeadlineContent
            } else {
                switch draft.proposal(for: draft.mode, currentWeightKg: currentWeightKg, energy: energy) {
                case nil:
                    if draft.targetWeightKg == nil {
                        NoticeLabel("目標体重を入れると、届く日の目安を計算します。")
                    } else {
                        NoticeLabel("いまの体重が分かると、届く日の目安を計算します。「自分で決める」で日付を選ぶこともできます。")
                    }
                case .alreadyAtGoal?:
                    NoticeLabel("いまの体重は、もう目標とほぼ同じです。この体重をキープしていきましょう。", style: .success)
                case .notReachableByDiet?:
                    NoticeLabel("食事の目安の下限を守ると、食事を控えるだけでは体重が減りにくい状態です。運動を増やすか、「自分で決める」で日付を選んでください。", style: .caution)
                case .proposed(let suggestion)?:
                    suggestionContent(suggestion)
                }
            }
        } header: {
            Text("目標に届く日の目安")
        } footer: {
            if let deadlineErrorMessage {
                FieldErrorText(deadlineErrorMessage)
            } else {
                Text("この日を期限として保存します。一般的な目安をもとにしたもので、医療的な判断ではありません。")
            }
        }
    }

    @ViewBuilder
    private func suggestionContent(_ suggestion: GoalDeadlineSuggestion) -> some View {
        MetricView(
            text: Text(suggestion.deadline, format: dateFormat(suggestion.deadline)),
            unit: "ごろ",
            caption: Text("\(durationText(GoalDeadlineProposer.duration(days: suggestion.days)))・1 週間に \(abs(suggestion.weeklyChangeKg), format: .number.precision(.fractionLength(0...2))) kg")
        )
        if suggestion.isLimitedByIntakeFloor {
            if suggestion.isSameForAllModes {
                NoticeLabel("食事の目安の下限を守るため、どちらのモードも同じ期限です。運動を増やすと早まることがあります。")
            } else {
                NoticeLabel("食事の目安の下限を守るため、少しゆっくりのペースにしています。運動を増やすと早まることがあります。")
            }
        }
        if suggestion.isBeyondHorizon {
            NoticeLabel("2 年より先になります。まずは手前の目標から始めると、達成を実感しやすくなります。")
        }
    }

    /// 保存した期限をそのまま出しているとき
    @ViewBuilder
    private var savedDeadlineContent: some View {
        let daysLeft = DayMath.days(from: .now, to: draft.deadline, calendar: .current)
        MetricView(
            text: Text(draft.deadline, format: dateFormat(draft.deadline)),
            unit: "まで",
            caption: Text("保存した期限です（あと \(daysLeft) 日）。")
        )
        NoticeLabel("目標体重かペースを変えると、今日から計算し直します。")
    }

    /// 日付の書き方：今年なら「3月1日」、来年以降なら「2028年3月1日」
    private func dateFormat(_ date: Date) -> Date.FormatStyle {
        let calendar = Calendar.current
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return .dateTime.month().day()
        }
        return .dateTime.year().month().day()
    }

    private func durationText(_ duration: GoalDuration) -> Text {
        switch duration {
        case .days(let days): Text("あと \(days) 日")
        case .weeks(let weeks): Text("約 \(weeks) 週間")
        case .months(let months, half: false): Text("約 \(months) か月")
        case .months(let months, half: true): Text("約 \(months) か月半")
        case .years(let years, months: 0): Text("約 \(years) 年")
        case .years(let years, months: let months): Text("約 \(years) 年 \(months) か月")
        }
    }

    // MARK: - BMI の目安

    private var bmiAdvice: GoalBMIAdvice? {
        GoalBMIAdvisor.advice(
            targetWeightKg: draft.targetWeightKg,
            currentWeightKg: currentWeightKg,
            heightCm: heightCm
        )
    }

    // MARK: - ペースのひとこと

    private var advice: GoalPlanAdvice {
        GoalPlanAdvisor.advice(
            targetWeightKg: draft.targetWeightKg,
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

extension GoalPaceMode {
    /// 画面に出すモードの名前
    var title: LocalizedStringKey {
        switch self {
        case .gentle: "ゆるやか"
        case .hard: "ハード"
        case .manual: "自分で決める"
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

    /// ゆるやか／ハードで期限を計算できなかったときに、期限の欄に出すメッセージ
    static var proposalUnavailableMessage: String {
        String(localized: "期限を計算できませんでした。「自分で決める」で日付を選んでください。")
    }
}

#Preview("ゆるやか（提案）") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(draft: $draft, currentWeightKg: 70, targetWeightErrorMessage: nil, deadlineErrorMessage: nil, heightCm: 165)
        }
    }
    .onAppear { draft.targetWeightText = "65.0" }
}

#Preview("食事の下限で止まる・大きい文字・ダークモード") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(
                draft: $draft,
                currentWeightKg: 55,
                targetWeightErrorMessage: nil,
                deadlineErrorMessage: nil,
                heightCm: 160,
                energy: DeadlineEnergy(tdeeKcal: 1427, minimumIntakeKcal: 1200)
            )
        }
    }
    .onAppear {
        draft.targetWeightText = "50.0"
        draft.mode = .hard
    }
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}

#Preview("自分で決める・無理のないペース") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(draft: $draft, currentWeightKg: 64.5, targetWeightErrorMessage: nil, deadlineErrorMessage: nil, heightCm: 160)
        }
    }
    .onAppear {
        draft.targetWeightText = "62.0"
        draft.mode = .manual
    }
}

#Preview("自分で決める・速すぎる・大きい文字・ダークモード") {
    @Previewable @State var draft = GoalDraft()
    NavigationStack {
        Form {
            GoalFormSections(draft: $draft, currentWeightKg: 64.5, targetWeightErrorMessage: nil, deadlineErrorMessage: nil, heightCm: 160)
        }
    }
    .onAppear {
        draft.targetWeightText = "50.0"
        draft.mode = .manual
    }
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
