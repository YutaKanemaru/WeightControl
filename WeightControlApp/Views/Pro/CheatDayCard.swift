import SwiftUI
import SwiftData

/// ホームの「チートデー」カード（Pro 機能・フェーズ 12）。仕様は docs/CHEAT_DAY.md。
///
/// 次のどれかのときだけ出します（どれでもなければカードごと出しません。「提案できません」とも言わない）。
/// - アプリが「チートデーにしてよさそう」と提案しているとき（計算は `CheatDaySuggestionAdvisor`）
/// - 今日から 7 日以内に、決めたチートデーがあるとき（取り消せるように）
/// - 昨日がチートデーだったとき（体重が少し増えても大丈夫、と伝えるため）
///
/// 日を選ぶと `CheatDay` として保存し、カレンダーにもスタンプが出ます。
struct CheatDayCard: View {
    /// 提案（提案しないときは nil）
    let suggestion: CheatDaySuggestion?
    /// 決めたチートデー（保存データ）
    let cheatDays: [CheatDay]
    /// 維持カロリー（kcal）。今日がチートデーのときに出す
    let maintenanceKcal: Double?

    @Environment(\.modelContext) private var modelContext
    /// 日を選んだときの「ぶるっ」という振動のきっかけ
    @State private var feedbackTrigger = 0

    private let calendar = Calendar.current

    /// カードを出すかどうか（ホーム側で判断するために static にしています）
    static func isVisible(suggestion: CheatDaySuggestion?, cheatDays: [CheatDay], now: Date = .now, calendar: Calendar = .current) -> Bool {
        if suggestion != nil { return true }
        let today = calendar.startOfDay(for: now)
        return cheatDays.contains {
            let offset = DayMath.days(from: today, to: $0.date, calendar: calendar)
            return (-1..<CheatDaySuggestionAdvisor.daysPerWeek).contains(offset)
        }
    }

    var body: some View {
        DashboardCard(title: "チートデー", systemImage: "fork.knife.circle", badge: "Pro") {
            if isTodayCheatDay {
                NoticeLabel(text: todayText, style: .success)
            } else if wasYesterdayCheatDay {
                NoticeLabel("昨日はチートデーでした。食べた量や塩分で、体重が一時的に増えるのはよくあることです。今日からまた、いつもどおりで大丈夫です。")
            }

            if let suggestion {
                suggestionContent(suggestion)
            }

            if !upcomingDays.isEmpty {
                upcomingList
            }

            NoticeLabel("食べ放題の日ではなく、体重を保つ量（維持カロリー）までの日です。記録をもとにアプリが提案しています。医療アドバイスではありません。")
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
    }

    // MARK: - 提案

    @ViewBuilder
    private func suggestionContent(_ suggestion: CheatDaySuggestion) -> some View {
        MetricView(
            "予定より",
            value: suggestion.aheadKg,
            unit: "kg 先に進んでいます",
            caption: Text("予定の線 \(suggestion.plannedWeightKg, format: kgFormat) kg・今の体重の目安 \(suggestion.currentWeightKg, format: kgFormat) kg"),
            size: .large,
            tint: .green
        )

        Text("この 7 日のうち \(suggestion.suggestedDays) 日まで、\(kcal(suggestion.cheatDayKcal)) kcal まで食べても期限に間に合う見込みです。ほかの日は今までどおり \(kcal(suggestion.regularDayKcal)) kcal が目安です。")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

        let today = calendar.startOfDay(for: .now)
        let tomorrow = DayMath.date(byAddingDays: 1, to: today, calendar: calendar)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { choiceButtons(suggestion, today: today, tomorrow: tomorrow) }
            VStack(alignment: .leading, spacing: 8) { choiceButtons(suggestion, today: today, tomorrow: tomorrow) }
        }
    }

    @ViewBuilder
    private func choiceButtons(_ suggestion: CheatDaySuggestion, today: Date, tomorrow: Date) -> some View {
        if suggestion.selectableDates.contains(today) {
            Button("今日にする") { add(today) }
                .buttonStyle(.borderedProminent)
        }
        if suggestion.selectableDates.contains(tomorrow) {
            Button("明日にする") { add(tomorrow) }
                .buttonStyle(.bordered)
        }
        Menu {
            ForEach(suggestion.selectableDates, id: \.self) { date in
                Button {
                    add(date)
                } label: {
                    Text(date, format: .dateTime.month().day().weekday())
                }
            }
        } label: {
            Label("日を選ぶ", systemImage: "calendar")
        }
        .buttonStyle(.bordered)
    }

    // MARK: - 決めたチートデー

    /// 今日から 7 日以内に決めたチートデー（古い順）
    private var upcomingDays: [CheatDay] {
        let today = calendar.startOfDay(for: .now)
        return cheatDays
            .filter { (0..<CheatDaySuggestionAdvisor.daysPerWeek).contains(DayMath.days(from: today, to: $0.date, calendar: calendar)) }
            .sorted { $0.date < $1.date }
    }

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("決めたチートデー")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(upcomingDays) { day in
                HStack {
                    Label {
                        Text(day.date, format: .dateTime.month().day().weekday())
                            .monospacedDigit()
                    } icon: {
                        StampIcon(kind: .cheatDay)
                    }
                    Spacer()
                    Button("取り消す", role: .destructive) {
                        withAnimation { modelContext.delete(day) }
                    }
                    .font(.callout)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - 当日・翌日

    private var isTodayCheatDay: Bool {
        cheatDays.contains { calendar.isDateInToday($0.date) }
    }

    private var wasYesterdayCheatDay: Bool {
        cheatDays.contains { calendar.isDateInYesterday($0.date) }
    }

    private var todayText: Text {
        if let maintenanceKcal {
            return Text("今日はチートデーです。目安は維持カロリーの \(kcal(maintenanceKcal)) kcal までです。楽しんでください。")
        }
        return Text("今日はチートデーです。体重を保つ量までを目安に、楽しんでください。")
    }

    // MARK: - 保存

    private func add(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        // 同じ日を二重に保存しない
        guard !cheatDays.contains(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return }
        withAnimation {
            modelContext.insert(CheatDay(date: day))
        }
        feedbackTrigger += 1
    }

    private func kcal(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}

private let kgFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

#Preview("提案あり") {
    let today = Calendar.current.startOfDay(for: .now)
    ScrollView {
        CheatDayCard(
            suggestion: CheatDaySuggestion(
                aheadKg: 0.8,
                plannedWeightKg: 70.9,
                currentWeightKg: 70.1,
                suggestedDays: 2,
                cheatDayKcal: 2300,
                regularDayKcal: 1800,
                costKgPerDay: 0.07,
                selectableDates: (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: today)! }
            ),
            cheatDays: [],
            maintenanceKcal: 2300
        )
        .padding()
    }
    .modelContainer(for: CheatDay.self, inMemory: true)
}

#Preview("今日がチートデー・大きい文字") {
    ScrollView {
        CheatDayCard(
            suggestion: nil,
            cheatDays: [CheatDay(date: Calendar.current.startOfDay(for: .now))],
            maintenanceKcal: 2300
        )
        .padding()
    }
    .dynamicTypeSize(.accessibility2)
    .modelContainer(for: CheatDay.self, inMemory: true)
}
