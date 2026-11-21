import SwiftUI
import SwiftData

/// 「ホーム」タブの画面：グラフ・達成の見込み・カロリーの目安・ほめるメッセージをまとめて見る画面。
///
/// 流れ：
/// 1. `@Query` で SwiftData から記録・プロフィール・目標を読む
/// 2. 計算用の値（`WeightPoint` など）に詰め替えて `HomeDashboardBuilder.build` に渡す
/// 3. 返ってきた結果（`HomeDashboard`）を、カードとして上から並べる
///
/// 記録や目標が変わると `@Query` が自動で画面を描き直すので、計算もそのたびにやり直されます。
struct HomeView: View {
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @Query private var profiles: [UserProfile]
    /// 目標は 1 件だけの想定。念のため新しい順に並べて先頭を使う。
    @Query(sort: \WeightGoal.startDate, order: .reverse) private var goals: [WeightGoal]

    /// ヘルスケア連携の係。連携していて運動データがあれば、消費カロリーの計算に実績を使う。
    @Environment(HealthSyncController.self) private var health: HealthSyncController?
    /// Pro を使えるか（使えるときだけ、見込みの幅とごほうびの日のカードを出す）
    @Environment(ProAccess.self) private var pro: ProAccess?

    @State private var isShowingAddSheet = false

    /// 食品カロリー表（アプリに同梱の JSON）。一度だけ読み込む。読めなければ空にして、ヒントを出さないだけにする。
    private static let foods: [FoodItem] = (try? FoodCatalog.loadBundledFoods()) ?? []

    var body: some View {
        let goal = goals.first
        let dashboard = HomeDashboardBuilder.build(
            points: entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) },
            profile: profiles.first?.dashboardProfile,
            goal: goal?.dashboardGoal,
            foods: Self.foods,
            healthActivity: health?.activitySummary,
            includesPro: isProUnlocked,
            now: .now
        )

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let latest = entries.first {
                        WeightSummaryCard(
                            latestKg: latest.weightKg,
                            latestDate: latest.date,
                            remainingKg: remainingKg(dashboard: dashboard, goal: goal),
                            goalWeightKg: goal?.targetWeightKg
                        )

                        PraiseCard(message: dashboard.praise, streakDays: dashboard.streakDays)

                        WeightChartCard(dashboard: dashboard, goalWeightKg: goal?.targetWeightKg, deadline: goal?.deadline)
                    } else {
                        EmptyRecordsCard { isShowingAddSheet = true }
                    }

                    if let goal {
                        if !entries.isEmpty, let forecast = dashboard.forecast {
                            ForecastCard(forecast: forecast)
                        }
                        if case .available(let range)? = dashboard.forecastRange {
                            ForecastRangeCard(range: range)
                        }
                        if case .tooAggressive(let correction)? = dashboard.safety {
                            GoalCorrectionCard(correction: correction, goal: goal, currentWeightKg: entries.first?.weightKg)
                        }
                        if let goalBMI = dashboard.goalBMI, goalBMI.needsHomeAttention {
                            GoalBMICard(advice: goalBMI, goal: goal, currentWeightKg: entries.first?.weightKg)
                        }
                    } else {
                        GoalPromptCard(currentWeightKg: entries.first?.weightKg)
                    }

                    if let intake = dashboard.intake {
                        IntakeCard(intake: intake, energyChoice: dashboard.energyChoice)
                        if isProUnlocked {
                            CheatDayLinkCard()
                        }
                    }

                    if let phrase = dashboard.calorieHint?.foodPhrase, let overPlan = dashboard.overPlanKcalPerDay {
                        FoodHintCard(foodPhrase: phrase, overPlanKcalPerDay: overPlan)
                    }

                    Text("予測やカロリーは一般的な計算式による目安です。このアプリは医療アドバイスではありません。体調に不安があるときは医師に相談してください。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("ホーム")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Label("体重を記録する", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                AddWeightEntryView(lastWeightKg: entries.first?.weightKg, lastEntryDate: entries.first?.date)
            }
        }
    }

    private var isProUnlocked: Bool { pro?.isUnlocked ?? false }

    /// 目標までの残り（kg）。目標や記録がなければ nil。
    ///
    /// 日によって増えたり減ったりしないよう、測った体重そのものではなく、
    /// 直近 3 週間の体重に引いた直線の今日の値（今の体重の目安）から計算します。
    private func remainingKg(dashboard: HomeDashboard, goal: WeightGoal?) -> Double? {
        guard let goal, let currentKg = dashboard.currentWeightKg else { return nil }
        return abs(goal.targetWeightKg - currentKg)
    }
}

// MARK: - プレビュー

/// プレビュー用の記録。`days` 日分、ゆるやかに減っている（`isFlat` なら横ばい）。目標なしにもできる。
@MainActor
private func homePreviewContainer(
    days: Int = 21,
    goalKg: Double? = 62,
    deadlineMonths: Int = 3,
    isFlat: Bool = false
) -> ModelContainer {
    let container = try! ModelContainer(
        for: WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    for daysAgo in 0..<days {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        // 日々のブレを少し入れる
        let noise = [0.0, 0.3, -0.2, 0.1, -0.1, 0.2, -0.3][daysAgo % 7]
        let weightKg = (isFlat ? 65.0 : 64.0 + 0.05 * Double(daysAgo)) + noise
        context.insert(WeightEntry(date: date, weightKg: weightKg))
    }
    context.insert(UserProfile(heightCm: 170, birthYear: 1990, sex: .male, activityLevel: .light))
    if let goalKg {
        let deadline = Calendar.current.date(byAdding: .month, value: deadlineMonths, to: .now)!
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        context.insert(WeightGoal(targetWeightKg: goalKg, deadline: deadline, startDate: start, startWeightKg: 65))
    }
    return container
}

#Preview("順調") {
    HomeView()
        .modelContainer(homePreviewContainer())
}

#Preview("Pro（見込みの幅・ごほうびの日）") {
    HomeView()
        .modelContainer(homePreviewContainer())
        .environment(ProAccess.previewUnlocked())
}

#Preview("順調・ダークモード") {
    HomeView()
        .modelContainer(homePreviewContainer())
        .preferredColorScheme(.dark)
}

#Preview("順調・大きい文字") {
    HomeView()
        .modelContainer(homePreviewContainer())
        .dynamicTypeSize(.accessibility2)
}

#Preview("記録 4 日（精度が低め）") {
    HomeView()
        .modelContainer(homePreviewContainer(days: 4))
}

#Preview("記録 2 日（まだ直線なし）") {
    HomeView()
        .modelContainer(homePreviewContainer(days: 2))
}

#Preview("横ばい（食べ物ヒント）") {
    HomeView()
        .modelContainer(homePreviewContainer(isFlat: true))
}

#Preview("目標が速すぎる") {
    HomeView()
        .modelContainer(homePreviewContainer(goalKg: 55, deadlineMonths: 1))
}

#Preview("目標なし") {
    HomeView()
        .modelContainer(homePreviewContainer(goalKg: nil))
}

#Preview("記録なし") {
    HomeView()
        .modelContainer(for: [WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self], inMemory: true)
}

#Preview("記録なし・ダークモード") {
    HomeView()
        .modelContainer(for: [WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self], inMemory: true)
        .preferredColorScheme(.dark)
}
