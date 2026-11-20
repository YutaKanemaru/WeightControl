import SwiftUI
import SwiftData

/// 「カレンダー」タブの画面：体重を測った日・運動した日にスタンプが押される月のカレンダー。
///
/// - 体重のスタンプ（緑）は、その日に体重を記録すると自動で押されます。
/// - 運動のスタンプ（オレンジ）は、日付をタップして自分で押します。もう一度タップすると取り消せます。
/// - 上のカードに「連続記録日数」と「今月のスタンプの数」を出して、続けている実感が持てるようにしています。
///
/// マス目の作り方やスタンプの数え方は `Logic/Calendar/` にあり、この画面は結果を並べるだけです。
struct StampCalendarView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var weightEntries: [WeightEntry]
    @Query private var exerciseDays: [ExerciseDay]

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
            calendar: calendar
        )
        let month = CalendarMonthBuilder.month(containing: displayedMonth, today: .now, calendar: calendar)

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    StreakSummaryCard(
                        streakDays: stampBook.weighInStreak(),
                        monthStampCount: stampBook.stampCount(inMonthContaining: displayedMonth),
                        exercisedToday: stampBook.hasExercise(on: .now),
                        onExerciseToday: { toggleExercise(on: .now) }
                    )

                    VStack(spacing: 12) {
                        monthHeader(month)
                        weekdayHeader(month)
                        monthGrid(month, stampBook: stampBook)
                    }
                    .padding()
                    .background(.background.secondary, in: .rect(cornerRadius: 20))

                    legend
                }
                .padding()
            }
            .navigationTitle("カレンダー")
            .sensoryFeedback(.success, trigger: stampFeedbackTrigger)
        }
    }

    // MARK: - 月の切り替え

    private func monthHeader(_ month: CalendarMonth) -> some View {
        let isCurrentMonth = calendar.isDate(month.monthStart, equalTo: .now, toGranularity: .month)
        return HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Label("前の月", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(month.monthStart, format: .dateTime.year().month(.wide))
                .font(.title3.bold())

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Label("次の月", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
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

    // MARK: - マス目

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private func weekdayHeader(_ month: CalendarMonth) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(zip(month.weekdayNumbers, month.weekdaySymbols)), id: \.0) { number, symbol in
                Text(symbol)
                    .font(.caption.bold())
                    .foregroundStyle(weekdayColor(number))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(_ month: CalendarMonth, stampBook: StampBook) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(month.cells.enumerated()), id: \.offset) { _, cell in
                if let cell {
                    CalendarDayCellView(
                        cell: cell,
                        hasWeighIn: stampBook.hasWeighIn(on: cell.date),
                        hasExercise: stampBook.hasExercise(on: cell.date)
                    ) {
                        toggleExercise(on: cell.date)
                    }
                } else {
                    Color.clear.frame(height: 56)
                }
            }
        }
    }

    /// 日曜は赤、土曜は青、ほかはふつうの色
    private func weekdayColor(_ weekdayNumber: Int) -> Color {
        switch weekdayNumber {
        case 1: .red
        case 7: .blue
        default: .secondary
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("体重を記録した日（自動）", systemImage: "scalemass.fill")
                .foregroundStyle(.green)
            Label("運動した日（日付をタップして押す）", systemImage: "figure.run")
                .foregroundStyle(.orange)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// カレンダーの 1 マス分：日付の数字と、押されたスタンプ
struct CalendarDayCellView: View {
    let cell: CalendarDayCell
    let hasWeighIn: Bool
    let hasExercise: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(verbatim: "\(cell.dayNumber)")
                    .font(.callout.monospacedDigit())
                    .fontWeight(cell.isToday ? .bold : .regular)
                    .foregroundStyle(cell.isFuture ? .tertiary : .primary)

                HStack(spacing: 2) {
                    stamp("scalemass.fill", color: .green, isOn: hasWeighIn)
                    stamp("figure.run", color: .orange, isOn: hasExercise)
                }
                .frame(height: 20)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(background, in: .rect(cornerRadius: 12))
            .overlay {
                if cell.isToday {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.tint, lineWidth: 2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(cell.isFuture)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(cell.isFuture ? Text(verbatim: "") : Text("ダブルタップで運動スタンプを押す・取り消す"))
    }

    /// スタンプ 1 つ。押されていないときは場所だけ確保して見えなくする（マスの高さがそろうように）
    private func stamp(_ systemName: String, color: Color, isOn: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color.gradient, in: .circle)
            .opacity(isOn ? 1 : 0)
            .scaleEffect(isOn ? 1 : 0.3)
            // スタンプが押された瞬間に、ぽんっと弾むアニメーション
            .symbolEffect(.bounce, value: isOn)
    }

    /// スタンプがある日は、ほんのり色をつける
    private var background: some ShapeStyle {
        if hasWeighIn && hasExercise {
            return AnyShapeStyle(Color.yellow.opacity(0.25))
        } else if hasWeighIn || hasExercise {
            return AnyShapeStyle(Color.accentColor.opacity(0.10))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    private var accessibilityText: String {
        var parts = [cell.date.formatted(.dateTime.month().day().weekday())]
        if hasWeighIn { parts.append(String(localized: "体重を記録済み")) }
        if hasExercise { parts.append(String(localized: "運動した")) }
        return parts.joined(separator: "、")
    }
}

/// 画面上部のカード：連続記録日数・今月のスタンプ数・「今日運動した」ボタン
struct StreakSummaryCard: View {
    let streakDays: Int
    let monthStampCount: Int
    let exercisedToday: Bool
    let onExerciseToday: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                statTile(
                    title: "連続記録",
                    value: "\(streakDays)",
                    unit: "日",
                    systemImage: "flame.fill",
                    color: .orange
                )
                statTile(
                    title: "今月のスタンプ",
                    value: "\(monthStampCount)",
                    unit: "個",
                    systemImage: "star.fill",
                    color: .yellow
                )
            }

            Text(encouragement)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button(action: onExerciseToday) {
                Label(
                    exercisedToday ? "今日の運動スタンプ、押せました！" : "今日、運動した！",
                    systemImage: exercisedToday ? "checkmark.seal.fill" : "figure.run"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(exercisedToday ? .green : .orange)
            .controlSize(.large)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }

    /// 責めずに、続けていることをほめるひとこと
    private var encouragement: LocalizedStringKey {
        switch streakDays {
        case 0: "今日の記録で、新しいスタンプを押しましょう。"
        case 1..<3: "いいスタートです！この調子で続けましょう。"
        case 3..<7: "\(streakDays)日続いています。習慣になってきましたね！"
        default: "\(streakDays)日連続！すばらしい習慣です。"
        }
    }

    private func statTile(
        title: LocalizedStringKey,
        value: String,
        unit: LocalizedStringKey,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.largeTitle.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StampCalendarView()
        .modelContainer(.preview())
}
