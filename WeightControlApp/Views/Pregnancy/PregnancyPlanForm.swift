import SwiftUI

/// 妊娠中モードの入力欄の下書き。始める画面と、設定を変える画面で使います。
///
/// 入力中の文字はそのまま持っておき、「始める」「保存」を押したときに数字に直します（打ちかけの値で画面がゆれないように）。
struct PregnancyPlanDraft: Equatable {
    /// 出産予定日を、日付で入れるか・今日の週数で入れるか
    enum DueDateInput: Hashable {
        case date
        case weeks
    }

    var dueDateInput: DueDateInput = .date
    var dueDate: Date
    var weeks = 8
    var days = 0
    var preWeightText = ""
    var isMultiple = false
    var customLowText = ""
    var customHighText = ""

    /// 新しく始めるとき（予定日はとりあえず今日から 200 日後）
    init(today: Date = .now) {
        dueDate = DayMath.date(byAddingDays: 200, to: today, calendar: .current)
    }

    /// 今の設定から
    init(plan: PregnancyPlan) {
        dueDate = plan.dueDate
        preWeightText = Self.kgText(plan.prePregnancyWeightKg)
        isMultiple = plan.isMultiple
        customLowText = plan.customGainLowKg.map(Self.kgText) ?? ""
        customHighText = plan.customGainHighKg.map(Self.kgText) ?? ""
    }

    static func kgText(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// 出産予定日（その日の 0 時）
    func resolvedDueDate(now: Date = .now) -> Date {
        switch dueDateInput {
        case .date: Calendar.current.startOfDay(for: dueDate)
        case .weeks: GestationalAgeCalculator.dueDate(weeks: weeks, days: days, on: now)
        }
    }

    /// 妊娠前の体重（kg）
    var preWeightResult: Result<Double, WeightInputParser.ParseError> {
        WeightInputParser.parse(preWeightText)
    }

    /// 妊娠前の体重の入力のまちがい（なければ nil）
    var preWeightErrorMessage: String? {
        guard case .failure(let error) = preWeightResult else { return nil }
        switch error {
        case .empty: return String(localized: "妊娠前の体重を入力してください。")
        case .notANumber: return String(localized: "数字で入力してください（例: 52.0）。")
        case .outOfRange: return String(localized: "20〜300 kg の範囲で入力してください。")
        }
    }

    /// 健診で言われた目安（下・上の値）。入れていなければ両方 nil。まちがいがあれば `customErrorMessage` に出す。
    var customRange: (lowKg: Double?, highKg: Double?) {
        guard customErrorMessage == nil else { return (nil, nil) }
        if case .value(let high) = PregnancyWeightGainGuide.parseGainText(customHighText) {
            if case .value(let low) = PregnancyWeightGainGuide.parseGainText(customLowText) {
                return (low, high)
            }
            return (nil, high)
        }
        return (nil, nil)
    }

    /// 健診で言われた目安の入力のまちがい（なければ nil）
    var customErrorMessage: String? {
        let low = PregnancyWeightGainGuide.parseGainText(customLowText)
        let high = PregnancyWeightGainGuide.parseGainText(customHighText)
        if low == .invalid || high == .invalid {
            return String(localized: "数字で入力してください（例: 10）。")
        }
        switch (low, high) {
        case (.empty, .empty):
            return nil
        case (.value, .empty):
            return String(localized: "上の値（「〜○ kg」）も入力してください。上の値だけでも大丈夫です。")
        case (_, .value(let highKg)):
            var lowKg: Double?
            if case .value(let value) = low { lowKg = value }
            switch PregnancyWeightGainGuide.validateCustomRange(lowKg: lowKg, highKg: highKg) {
            case .outOfRange?: return String(localized: "0〜30 kg の範囲で入力してください。")
            case .lowAboveHigh?: return String(localized: "左の値は、右の値以下にしてください。")
            case nil: return nil
            }
        default:
            return nil
        }
    }

    /// 始める・保存できるか
    var isValid: Bool {
        preWeightErrorMessage == nil && customErrorMessage == nil
    }

    /// 設定に書きこむ
    func apply(to plan: PregnancyPlan, now: Date = .now) {
        plan.dueDate = resolvedDueDate(now: now)
        if case .success(let kg) = preWeightResult {
            plan.prePregnancyWeightKg = kg
        }
        plan.isMultiple = isMultiple
        let range = customRange
        plan.customGainLowKg = range.lowKg
        plan.customGainHighKg = range.highKg
    }
}

/// 妊娠中モードの入力欄（Form の中に置く Section たち）
struct PregnancyPlanFormSections: View {
    @Binding var draft: PregnancyPlanDraft
    /// 身長（cm）。妊娠前の BMI と目安を、その場で見せるのに使う
    let heightCm: Double
    /// 妊娠前の体重の候補（記録から）。なければ nil
    let preWeightSuggestionKg: Double?

    private let kgFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

    var body: some View {
        dueDateSection
        preWeightSection
        babiesSection
        customRangeSection
    }

    // MARK: - 出産予定日

    private var dueDateSection: some View {
        Section {
            Picker("入れ方", selection: $draft.dueDateInput) {
                Text("予定日で入れる").tag(PregnancyPlanDraft.DueDateInput.date)
                Text("今の週数で入れる").tag(PregnancyPlanDraft.DueDateInput.weeks)
            }
            .pickerStyle(.segmented)

            switch draft.dueDateInput {
            case .date:
                DatePicker("出産予定日", selection: $draft.dueDate, in: dueDateRange, displayedComponents: .date)
            case .weeks:
                Picker("週", selection: $draft.weeks) {
                    ForEach(Array(GestationalAgeCalculator.enterableWeeks), id: \.self) { week in
                        Text("\(week) 週").tag(week)
                    }
                }
                Picker("日", selection: $draft.days) {
                    ForEach(0..<7, id: \.self) { day in
                        Text("\(day) 日").tag(day)
                    }
                }
            }

            let age = GestationalAgeCalculator.age(dueDate: draft.resolvedDueDate(), on: .now)
            LabeledContent("今日") {
                gestationalAgeText(age)
                    .monospacedDigit()
            }
            if draft.dueDateInput == .weeks {
                LabeledContent("出産予定日") {
                    Text(draft.resolvedDueDate(), format: .dateTime.year().month().day())
                }
            }
        } header: {
            Text("出産予定日")
        } footer: {
            Text("母子健康手帳や健診で言われた予定日を入れてください。予定日を妊娠 40 週 0 日として、週数を数えます。")
        }
    }

    /// 選べる予定日：今日の 30 日前〜300 日後
    private var dueDateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        return DayMath.date(byAddingDays: -30, to: today, calendar: .current)...DayMath.date(byAddingDays: 300, to: today, calendar: .current)
    }

    // MARK: - 妊娠前の体重

    private var preWeightSection: some View {
        Section {
            HStack {
                TextField("妊娠前の体重", text: $draft.preWeightText, prompt: Text(verbatim: "52.0"))
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                Text("kg")
                    .foregroundStyle(.secondary)
            }
            if let preWeightSuggestionKg, draft.preWeightText.isEmpty {
                Button {
                    draft.preWeightText = PregnancyPlanDraft.kgText(preWeightSuggestionKg)
                } label: {
                    Label("妊娠前の記録から入れる（\(preWeightSuggestionKg, format: kgFormat) kg）", systemImage: "arrow.down.doc")
                }
            }
            if case .success(let kg) = draft.preWeightResult, heightCm > 0 {
                let bmi = BodyMetrics.bmi(weightKg: kg, heightCm: heightCm)
                let bodyType = PrePregnancyBodyType.classify(bmi: bmi)
                LabeledContent {
                    Text("\(bmi, format: .number.precision(.fractionLength(1)))（\(bodyType.title)）")
                        .monospacedDigit()
                } label: {
                    Text("妊娠前の BMI")
                }
            }
        } header: {
            Text("妊娠前の体重")
        } footer: {
            if let message = draft.preWeightErrorMessage, !draft.preWeightText.isEmpty {
                FieldErrorText(message)
            } else {
                Text("妊娠がわかる前のふだんの体重です。妊娠前の体格（BMI）で、増え方の目安が変わります。")
            }
        }
    }

    // MARK: - 赤ちゃんの人数

    private var babiesSection: some View {
        Section {
            Picker("おなかの赤ちゃん", selection: $draft.isMultiple) {
                Text("1 人").tag(false)
                Text("2 人以上").tag(true)
            }
        } footer: {
            if draft.isMultiple {
                Text("双子などのときは、アプリから一般的な目安は出しません。健診で言われた目安を下に入れると、その目安で見られます。")
            }
        }
    }

    // MARK: - 健診で言われた目安

    private var customRangeSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("下の値", text: $draft.customLowText, prompt: Text(verbatim: "10"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("〜")
                    .foregroundStyle(.secondary)
                TextField("上の値", text: $draft.customHighText, prompt: Text(verbatim: "13"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("kg")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("健診で言われた目安"))
        } header: {
            Text("健診で言われた目安（任意）")
        } footer: {
            if let message = draft.customErrorMessage {
                FieldErrorText(message)
            } else {
                Text("出産までに増やす体重の合計です。健診で目安を言われたら、ここに入れるとその数字で見られます（「○ kg まで」なら右だけで大丈夫です）。入れていないときは、一般的な目安を使います。")
            }
        }
    }
}
