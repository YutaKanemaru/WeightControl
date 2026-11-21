import SwiftUI
import SwiftData

/// 「カレンダー」タブの画面：体重を測った日・運動した日にスタンプが押される月のカレンダー。
///
/// 上から 3 枚のカードを並べます（ホームと同じ `DashboardCard`）。
/// 1. 続けている記録：連続記録日数（大きな数字）と今月のスタンプの数。まだ記録がなければ使いかたの案内。
/// 2. 今日のスタンプ：体重は記録すると自動で押され、運動はボタンで押せる。
/// 3. カレンダー：月のマス目。日付をタップすると運動スタンプを押す・取り消す。
///
/// マス目の作り方・スタンプの数え方・ひとことの選び方は `Logic/Calendar/` にあり、この画面は結果を並べるだけです。
struct StampCalendarView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var weightEntries: [WeightEntry]
    @Query private var exerciseDays: [ExerciseDay]
    /// チートデー（Pro）。Pro を使えるときだけカレンダーに印を出す
    @Query private var cheatDays: [CheatDay]
    @Environment(ProAccess.self) private var pro: ProAccess?

    /// いま表示している月（その月の 1 日）
    @State private var displayedMonth = CalendarMonthBuilder.monthStart(for: .now, calendar: .current)
    /// スタンプを押したときの「ぶるっ」という振動（ハプティクス）のきっかけ
    @State private var stampFeedbackTrigger = 0

    private let calendar = Calendar.current

    var body: some View {
        // 体重・運動の日付を「スタンプ帳」にまとめる（計算は Logic 側）
        let stampBook = StampBook(
            weighInDates: weightEntries.map(\.date),
            exerciseDates: exerciseDays.map(\.date),
            cheatDayDates: showsCheatDays ? cheatDays.map(\.date) : [],
            calendar: calendar
        )
        let summary = CalendarSummaryBuilder.build(stampBook: stampBook, today: .now)
        let month = CalendarMonthBuilder.month(containing: displayedMonth, today: .now, calendar: calendar)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if summary.hasAnyStamp {
                        StreakSummaryCard(summary: summary)
                    } else {
                        EmptyStampsCard()
                    }

                    TodayStampCard(summary: summary) {
                        toggleExercise(on: .now)
                    }

                    DashboardCard(title: "スタンプカレンダー", systemImage: "calendar") {
                        VStack(spacing: 12) {
                            monthHeader(month)
                            StampMonthGrid(month: month, stampBook: stampBook) { date in
                                toggleExercise(on: date)
                            }
                            monthFooter(stampBook: stampBook)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("カレンダー")
            .sensoryFeedback(.success, trigger: stampFeedbackTrigger)
        }
    }

    /// チートデーの印を出すか（Pro を使えるときだけ）
    private var showsCheatDays: Bool { pro?.isUnlocked ?? false }

    // MARK: - 月の切り替え

    private func monthHeader(_ month: CalendarMonth) -> some View {
        let isCurrentMonth = calendar.isDate(month.monthStart, equalTo: .now, toGranularity: .month)
        return HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Label("前の月", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }

            Spacer()

            Text(month.monthStart, format: .dateTime.year().month(.wide))
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Label("次の月", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            // 未来の月にはスタンプがないので、今月より先には進めない
            .disabled(isCurrentMonth)
        }
    }

    private func moveMonth(by months: Int) {
        withAnimation(.snappy) {
            displayedMonth = CalendarMonthBuilder.month(byAdding: months, to: displayedMonth, calendar: calendar)
        }
    }

    /// 表示している月の内訳と、スタンプの見かた（凡例）
    private func monthFooter(stampBook: StampBook) -> some View {
        let weighIns = stampBook.weighInCount(inMonthContaining: displayedMonth)
        let exercises = stampBook.exerciseCount(inMonthContaining: displayedMonth)
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label {
                Text("体重を記録した日 \(weighIns)日（記録すると自動で押されます）")
            } icon: {
                StampIcon(kind: .weighIn)
            }
            Label {
                Text("運動した日 \(exercises)日（日付をタップして押せます）")
            } icon: {
                StampIcon(kind: .exercise)
            }
            if showsCheatDays {
                Label {
                    Text("チートデー \(stampBook.cheatDayCount(inMonthContaining: displayedMonth))日（ホームのカードで決められます）")
                } icon: {
                    StampIcon(kind: .cheatDay)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 運動スタンプの保存

    /// 日付をタップしたときに、運動スタンプを押す・取り消す
    private func toggleExercise(on date: Date) {
        let day = calendar.startOfDay(for: date)
        let sameDay = exerciseDays.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let manual = sameDay.filter { $0.source == .manual }

        let action = ExerciseStampRule.action(
            forTapOn: day,
            hasManualStamp: !manual.isEmpty,
            hasAutomaticStamp: sameDay.contains { $0.source != .manual },
            calendar: calendar
        )

        withAnimation(.bouncy) {
            switch action {
            case .add:
                modelContext.insert(ExerciseDay(date: day, source: .manual))
                stampFeedbackTrigger += 1
            case .remove:
                manual.forEach { modelContext.delete($0) }
            case .none:
                break
            }
        }
    }
}

// MARK: - スタンプの絵

/// スタンプ 1 つ分の絵。SF Symbols のアイコンを、意味のある色（体重＝緑、運動＝オレンジ、チートデー＝アクセントカラー）の丸の上に白で描きます。
///
/// 大きさは `@ScaledMetric` で文字サイズの設定に合わせて伸び縮みします。
struct StampIcon: View {
    enum Kind {
        /// 体重を記録した日
        case weighIn
        /// 運動した日
        case exercise
        /// チートデー（Pro）
        case cheatDay

        var systemImage: String {
            switch self {
            case .weighIn: "scalemass.fill"
            case .exercise: "figure.run"
            case .cheatDay: "fork.knife"
            }
        }

        var color: Color {
            switch self {
            case .weighIn: .green
            case .exercise: .orange
            case .cheatDay: .accentColor
            }
        }
    }

    let kind: Kind

    /// 丸の直径（pt）。文字サイズに合わせて大きくなる。
    @ScaledMetric(relativeTo: .caption) private var diameter: CGFloat = 18

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: diameter * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(kind.color.gradient, in: .circle)
            // 絵そのものは読み上げない（読み上げはマスやカードの説明文でまとめて行う）
            .accessibilityHidden(true)
    }
}

// MARK: - カード

/// スタンプがあるときの上のカード：連続記録日数を大きく、今月のスタンプ数をその横（大きい文字では下）に。
struct StreakSummaryCard: View {
    let summary: CalendarSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        DashboardCard(title: "続けている記録", systemImage: "flame.fill") {
            // 大きい文字のときは横に並べると入りきらないので、縦に積む
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

            layout {
                MetricView(
                    "連続記録",
                    text: Text(summary.streakDays, format: .number),
                    unit: "日",
                    caption: summary.hasWeighInToday ? Text("今日も記録できました") : Text("体重を記録した日が続いた数"),
                    size: .hero
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                MetricView(
                    "今月のスタンプ",
                    text: Text(summary.monthStampCount, format: .number),
                    unit: "個",
                    caption: Text("体重 \(summary.monthWeighInDays)日・運動 \(summary.monthExerciseDays)日"),
                    size: .large
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            NoticeLabel(text: encouragementText, style: isHabit ? .success : .info)
        }
    }

    private var isHabit: Bool {
        if case .habit = summary.encouragement { return true }
        return false
    }

    /// 責めずに、続けていることをほめるひとこと
    private var encouragementText: Text {
        switch summary.encouragement {
        case .firstStamp:
            Text("体重を記録すると、最初のスタンプが押されます。")
        case .restart:
            Text("今日の記録から、また新しく始めましょう。")
        case .goodStart:
            Text("いいスタートです！この調子で続けましょう。")
        case .buildingHabit(let days):
            Text("\(days)日続いています。習慣になってきましたね！")
        case .habit(let days):
            Text("\(days)日連続！すばらしい習慣です。")
        }
    }
}

/// まだスタンプが 1 つもないときの上のカード：スタンプのしくみを案内する（空の状態）
struct EmptyStampsCard: View {
    var body: some View {
        DashboardCard(title: "スタンプをためよう", systemImage: "star") {
            Text("記録した日にスタンプが押されます。続けた日数が、ここに大きく表示されます。")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("「記録」タブで体重を記録すると、自動で押されます")
                } icon: {
                    StampIcon(kind: .weighIn)
                }
                Label {
                    Text("運動した日は、下のボタンかカレンダーの日付をタップ")
                } icon: {
                    StampIcon(kind: .exercise)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

/// 今日のスタンプのカード：体重のスタンプの状態と、「今日、運動した！」ボタン
struct TodayStampCard: View {
    let summary: CalendarSummary
    let onToggleExercise: () -> Void

    var body: some View {
        DashboardCard(title: "今日のスタンプ", systemImage: "checkmark.seal") {
            Label {
                Text(summary.hasWeighInToday ? "体重のスタンプ、押せました" : "体重を記録すると押されます")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                StampIcon(kind: .weighIn)
                    .opacity(summary.hasWeighInToday ? 1 : 0.35)
            }
            .font(.subheadline)
            .foregroundStyle(summary.hasWeighInToday ? .primary : .secondary)
            .accessibilityElement(children: .combine)

            Button(action: onToggleExercise) {
                Label(
                    summary.hasExerciseToday ? "今日の運動スタンプ、押せました！" : "今日、運動した！",
                    systemImage: summary.hasExerciseToday ? "checkmark.circle.fill" : "figure.run"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(summary.hasExerciseToday ? .green : .orange)
            .controlSize(.large)
            .accessibilityHint(summary.hasExerciseToday ? Text("ダブルタップで取り消す") : Text("ダブルタップで運動スタンプを押す"))
        }
    }
}

// MARK: - マス目

/// 1 か月分のマス目（曜日の見出し＋日付のマス）
struct StampMonthGrid: View {
    let month: CalendarMonth
    let stampBook: StampBook
    let onTapDay: (Date) -> Void

    /// マスの高さ（pt）。文字サイズに合わせて大きくなる。
    @ScaledMetric(relativeTo: .callout) private var cellHeight: CGFloat = 56

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(zip(month.weekdayNumbers, month.weekdaySymbols)), id: \.0) { number, symbol in
                    Text(symbol)
                        .font(.caption.bold())
                        .foregroundStyle(weekdayColor(number))
                        .frame(maxWidth: .infinity)
                        // 曜日の 1 文字は読み上げると分かりにくいので、各マスの説明に曜日を入れて読む
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(month.cells.enumerated()), id: \.offset) { _, cell in
                    if let cell {
                        CalendarDayCellView(
                            cell: cell,
                            hasWeighIn: stampBook.hasWeighIn(on: cell.date),
                            hasExercise: stampBook.hasExercise(on: cell.date),
                            hasCheatDay: stampBook.hasCheatDay(on: cell.date),
                            height: cellHeight
                        ) {
                            onTapDay(cell.date)
                        }
                    } else {
                        Color.clear
                            .frame(height: cellHeight)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        // 7 列のマス目は、とても大きい文字にすると数字が入りきらないので、大きくなるのはここまでにする
        // （同じ内容は VoiceOver と下の内訳でも読めます）
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// 日曜は赤、土曜は青、ほかは控えめな色（日本のカレンダーの見慣れた色づかい）
    private func weekdayColor(_ weekdayNumber: Int) -> Color {
        switch weekdayNumber {
        case 1: .red
        case 7: .blue
        default: .secondary
        }
    }
}

/// カレンダーの 1 マス分：日付の数字と、押されたスタンプ
struct CalendarDayCellView: View {
    let cell: CalendarDayCell
    let hasWeighIn: Bool
    let hasExercise: Bool
    /// チートデー（Pro）か。未来の日にもつく
    var hasCheatDay: Bool = false
    let height: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(verbatim: "\(cell.dayNumber)")
                    .font(.callout.monospacedDigit())
                    .fontWeight(cell.isToday ? .bold : .regular)
                    .foregroundStyle(cell.isFuture ? .tertiary : .primary)

                HStack(spacing: 2) {
                    stamp(.weighIn, isOn: hasWeighIn)
                    stamp(.exercise, isOn: hasExercise)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .background(background, in: .rect(cornerRadius: 12))
            .overlay {
                if cell.isToday {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.tint, lineWidth: 2)
                }
            }
            // チートデーの印はマスの右上に小さく（スタンプ 3 つは横に入りきらないため）
            .overlay(alignment: .topTrailing) {
                if hasCheatDay {
                    StampIcon(kind: .cheatDay)
                        .scaleEffect(0.75)
                        .offset(x: 3, y: -3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(cell.isFuture)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(cell.isFuture ? Text(verbatim: "") : Text("ダブルタップで運動スタンプを押す・取り消す"))
    }

    /// スタンプ 1 つ。押されていないときは場所だけ確保して見えなくする（マスの高さがそろうように）
    private func stamp(_ kind: StampIcon.Kind, isOn: Bool) -> some View {
        StampIcon(kind: kind)
            .opacity(isOn ? 1 : 0)
            .scaleEffect(isOn ? 1 : 0.3)
    }

    /// スタンプがある日は、アクセントカラーでほんのり色をつける（両方ある日は少し濃く）
    private var background: some ShapeStyle {
        switch (hasWeighIn, hasExercise) {
        case (true, true): AnyShapeStyle(Color.accentColor.opacity(0.22))
        case (true, false), (false, true): AnyShapeStyle(Color.accentColor.opacity(0.10))
        case (false, false): AnyShapeStyle(Color.clear)
        }
    }

    /// VoiceOver で最初に読む部分：「11月20日 金曜日、今日」
    private var accessibilityLabelText: String {
        let dateText = cell.date.formatted(.dateTime.month().day().weekday(.wide))
        return cell.isToday ? dateText + "、" + String(localized: "今日") : dateText
    }

    /// VoiceOver で続けて読む部分：押されたスタンプ
    private var accessibilityValueText: String {
        var parts: [String] = []
        if hasWeighIn { parts.append(String(localized: "体重を記録済み")) }
        if hasExercise { parts.append(String(localized: "運動した")) }
        if hasCheatDay { parts.append(String(localized: "チートデー")) }
        return parts.isEmpty ? String(localized: "スタンプなし") : parts.joined(separator: "、")
    }
}

// MARK: - プレビュー

/// 記録が 1 つもない状態のプレビュー用データベース（メモリ上だけ）
@MainActor
private func emptyCalendarPreviewContainer() -> ModelContainer {
    try! ModelContainer(
        for: WeightEntry.self, ExerciseDay.self, CheatDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

#Preview("記録あり") {
    StampCalendarView()
        .modelContainer(.preview())
}

#Preview("記録あり・ダークモード") {
    StampCalendarView()
        .modelContainer(.preview())
        .preferredColorScheme(.dark)
}

#Preview("記録あり・大きい文字") {
    StampCalendarView()
        .modelContainer(.preview())
        .dynamicTypeSize(.accessibility3)
}

#Preview("空の状態") {
    StampCalendarView()
        .modelContainer(emptyCalendarPreviewContainer())
}

#Preview("空の状態・ダークモード") {
    StampCalendarView()
        .modelContainer(emptyCalendarPreviewContainer())
        .preferredColorScheme(.dark)
}
