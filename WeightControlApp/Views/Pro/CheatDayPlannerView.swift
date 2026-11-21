import SwiftUI
import SwiftData

/// 「ごほうびの日の計画」画面（Pro 機能・フェーズ 12）。
///
/// 今日から 7 日のうち、飲み会などで多めに食べたい日（ごほうびの日）を 1〜2 日選ぶと、
/// 「ふだんの日は何 kcal・ごほうびの日は何 kcal」を出します。1 週間の合計（予算）は変わりません。
///
/// 流れ：
/// 1. ホームと同じく `HomeDashboardBuilder` で、1 日の摂取カロリーの目安・下限・消費カロリーの目安を出す
/// 2. 選んだ日と一緒に `CheatDayBudgetPlanner.plan` に渡す
/// 3. 返ってきた計画を、標準の `List` に並べる
///
/// 決まり（週 2 日まで・1 日 300 kcal まで・ごほうびの日も維持カロリーまで）は docs/CHEAT_DAY.md。
/// 選んだ日は保存しません（画面を閉じると選び直し）。
struct CheatDayPlannerView: View {
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightGoal.startDate, order: .reverse) private var goals: [WeightGoal]
    @Environment(HealthSyncController.self) private var health: HealthSyncController?
    @Environment(ProAccess.self) private var pro: ProAccess?

    /// ごほうびの日にした日（今日を 0 とした何日目か）
    @State private var cheatDayOffsets: Set<Int> = []
    /// 多めに食べたい量を自分で決めるか（オフなら、決まりの範囲でできるだけ多く貯める）
    @State private var usesDesiredExtra = false
    /// ごほうびの日に、いつもより多く食べたい量（kcal）
    @State private var desiredExtraKcal = 500.0

    var body: some View {
        Group {
            if pro?.isUnlocked == true {
                planner
            } else {
                ProLockedView()
            }
        }
        .navigationTitle("ごほうびの日の計画")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 計算

    private func makeDashboard() -> HomeDashboard {
        HomeDashboardBuilder.build(
            points: entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) },
            profile: profiles.first?.dashboardProfile,
            goal: goals.first?.dashboardGoal,
            foods: [],
            healthActivity: health?.activitySummary,
            now: .now
        )
    }

    private var startDate: Date { Calendar.current.startOfDay(for: .now) }

    private func date(at offset: Int) -> Date {
        DayMath.date(byAddingDays: offset, to: startDate, calendar: .current)
    }

    // MARK: - 画面

    @ViewBuilder
    private var planner: some View {
        let dashboard = makeDashboard()
        if let intake = dashboard.intake, let minimumKcal = dashboard.minimumIntakeKcal {
            let result = CheatDayBudgetPlanner.plan(
                dailyTargetKcal: intake.targetKcal,
                minimumIntakeKcal: minimumKcal,
                startDate: startDate,
                cheatDates: cheatDayOffsets.map { date(at: $0) },
                desiredCheatDayExtraKcal: usesDesiredExtra ? desiredExtraKcal : nil,
                maintenanceKcal: intake.tdeeKcal
            )
            let plan: CheatDayPlan? = if case .available(let value) = result { value } else { nil }

            List {
                summarySection(plan: plan, intake: intake)
                daysSection(plan: plan, intake: intake)
                desiredExtraSection
                if let plan, let limit = plan.limit {
                    Section {
                        NoticeLabel(text: limitText(limit, intake: intake, minimumKcal: minimumKcal))
                    }
                }
                rulesSection
            }
        } else {
            ContentUnavailableView {
                Label("まだ計画できません", systemImage: "fork.knife")
            } description: {
                Text("プロフィールと体重の記録があると、1 日の摂取カロリーの目安から計画を立てられます。")
            }
        }
    }

    /// いちばん大事な数字：ふだんの日とごほうびの日の kcal
    @ViewBuilder
    private func summarySection(plan: CheatDayPlan?, intake: IntakeRecommendation) -> some View {
        Section {
            if let plan {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { summaryMetrics(plan) }
                    VStack(alignment: .leading, spacing: 12) { summaryMetrics(plan) }
                }
                .padding(.vertical, 4)
            } else {
                MetricView(
                    "1 日の摂取カロリーの目安",
                    value: intake.targetKcal.rounded(),
                    fractionLength: 0,
                    unit: "kcal",
                    caption: Text("下の一覧から、ごほうびの日を 1〜\(CheatDayBudgetPlanner.maximumCheatDays) 日選んでください。"),
                    size: .medium
                )
                .padding(.vertical, 4)
            }
        } footer: {
            Text("1 週間の予算 \(kcal(intake.targetKcal * Double(CheatDayBudgetPlanner.daysPerWeek))) kcal（1 日の目安 × 7）は変わりません。")
        }
    }

    @ViewBuilder
    private func summaryMetrics(_ plan: CheatDayPlan) -> some View {
        MetricView(
            "ふだんの日",
            value: plan.regularDayKcal.rounded(),
            fractionLength: 0,
            unit: "kcal",
            caption: Text("いつもより −\(kcal(plan.dailySavingKcal)) kcal"),
            size: .medium
        )
        MetricView(
            "ごほうびの日",
            value: plan.cheatDayKcal.rounded(),
            fractionLength: 0,
            unit: "kcal",
            caption: Text("いつもより ＋\(kcal(plan.cheatDayExtraKcal)) kcal"),
            size: .medium,
            tint: .accentColor
        )
    }

    /// 今日から 7 日分。タップでごほうびの日にする・やめる
    private func daysSection(plan: CheatDayPlan?, intake: IntakeRecommendation) -> some View {
        Section {
            ForEach(0..<CheatDayBudgetPlanner.daysPerWeek, id: \.self) { offset in
                let isCheatDay = cheatDayOffsets.contains(offset)
                let dayKcal = plan?.days[offset].intakeKcal ?? intake.targetKcal
                let isFull = cheatDayOffsets.count >= CheatDayBudgetPlanner.maximumCheatDays
                Button {
                    toggle(offset)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isCheatDay ? "gift.fill" : "circle")
                            .foregroundStyle(isCheatDay ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(date(at: offset), format: .dateTime.month().day().weekday(.abbreviated))
                                .foregroundStyle(.primary)
                            if offset == 0 {
                                Text("今日")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("\(kcal(dayKcal)) kcal")
                            .font(.body.weight(isCheatDay ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isCheatDay ? Color.accentColor : Color.primary)
                    }
                    .contentShape(.rect)
                }
                .disabled(!isCheatDay && isFull)
                .accessibilityAddTraits(isCheatDay ? .isSelected : [])
                .accessibilityHint(isCheatDay ? Text("ごほうびの日をやめます") : Text("ごほうびの日にします"))
            }
        } header: {
            Text("ごほうびにする日")
        } footer: {
            Text("1 週間に \(CheatDayBudgetPlanner.maximumCheatDays) 日まで選べます。予定どおりにいかない日があっても大丈夫です。")
        }
    }

    private var desiredExtraSection: some View {
        Section {
            Toggle("多めに食べたい量を決める", isOn: $usesDesiredExtra)
            if usesDesiredExtra {
                Stepper(value: $desiredExtraKcal, in: 100...2000, step: 100) {
                    LabeledContent("いつもより多く") {
                        Text("\(kcal(desiredExtraKcal)) kcal")
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("ごほうびの日の量")
        } footer: {
            Text("オフのときは、決まりの範囲でできるだけ多く貯めます。")
        }
    }

    private var rulesSection: some View {
        Section {
            InfoPointRow(
                title: "ふだんの日は 1 日 \(kcal(CheatDayBudgetPlanner.maximumDailySavingKcal)) kcal まで",
                detail: "急に大きく減らすと続けにくいので、控えめにするのは少しだけ。体のための下限も下回りません。",
                systemImage: "tortoise"
            )
            InfoPointRow(
                title: "ごほうびの日も維持カロリーまで",
                detail: "体重が増えも減りもしない量（消費カロリーの目安）までにしています。食べ放題の日にはしません。",
                systemImage: "scalemass"
            )
        } header: {
            Text("この計画の決まり")
        } footer: {
            Text("研究や一般的な目安をもとにした計算で、医療アドバイスではありません。体調に不安があるときは医師に相談してください。")
        }
    }

    // MARK: - 補助

    private func toggle(_ offset: Int) {
        if cheatDayOffsets.contains(offset) {
            cheatDayOffsets.remove(offset)
        } else if cheatDayOffsets.count < CheatDayBudgetPlanner.maximumCheatDays {
            cheatDayOffsets.insert(offset)
        }
    }

    /// kcal を整数の文字列に（例: 1,850）
    private func kcal(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    /// 希望どおりに貯められなかった理由の説明（責めない言い方で）
    private func limitText(_ limit: CheatDayPlanLimit, intake: IntakeRecommendation, minimumKcal: Double) -> Text {
        switch limit {
        case .maintenance:
            if intake.targetKcal >= intake.tdeeKcal {
                return Text("いまの目標では、1 日の目安が維持カロリー（約 \(kcal(intake.tdeeKcal)) kcal）と同じくらいなので、ごほうびの日の上乗せはありません。")
            }
            return Text("ごほうびの日も、維持カロリー（体重が増えも減りもしない量の目安、約 \(kcal(intake.tdeeKcal)) kcal）までにしています。")
        case .minimumIntake:
            return Text("ふだんの日も、体のための下限（約 \(kcal(minimumKcal)) kcal）を下回らないようにしています。")
        case .dailySaving:
            return Text("続けやすいよう、ふだんの日に控えめにするのは 1 日 \(kcal(CheatDayBudgetPlanner.maximumDailySavingKcal)) kcal までにしています。")
        }
    }
}

#Preview("Pro を試し中") {
    NavigationStack {
        CheatDayPlannerView()
    }
    .modelContainer(.preview())
    .environment(ProAccess.previewUnlocked())
}

#Preview("大きい文字・ダークモード") {
    NavigationStack {
        CheatDayPlannerView()
    }
    .modelContainer(.preview())
    .environment(ProAccess.previewUnlocked())
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}

#Preview("Pro なし") {
    NavigationStack {
        CheatDayPlannerView()
    }
    .modelContainer(.preview())
    .environment(ProAccess())
}
