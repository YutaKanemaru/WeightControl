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
            now: .now
        )

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PraiseCard(message: dashboard.praise, streakDays: dashboard.streakDays)

                    if entries.isEmpty {
                        emptyState
                    } else {
                        summary(dashboard: dashboard, goal: goal)

                        DashboardCard(title: "体重の流れ", systemImage: "chart.xyaxis.line") {
                            WeightChartView(
                                trend: dashboard.trend,
                                forecastLine: dashboard.forecastLine,
                                goalWeightKg: goal?.targetWeightKg
                            )
                        }
                    }

                    ForecastCard(forecast: dashboard.forecast)

                    if case .tooAggressive(let correction)? = dashboard.safety, let goal {
                        GoalCorrectionCard(correction: correction, goal: goal, currentWeightKg: entries.first?.weightKg)
                    }

                    if let intake = dashboard.intake {
                        IntakeCard(intake: intake)
                    }

                    if let phrase = dashboard.calorieHint?.foodPhrase, let overPlan = dashboard.overPlanKcalPerDay {
                        FoodHintCard(foodPhrase: phrase, overPlanKcalPerDay: overPlan)
                    }

                    if goal == nil {
                        NavigationLink("目標を決める") {
                            EditGoalView(goal: nil, currentWeightKg: entries.first?.weightKg)
                        }
                        .buttonStyle(.borderedProminent)
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
                AddWeightEntryView(lastWeightKg: entries.first?.weightKg)
            }
        }
    }

    /// いまの体重・トレンド・目標まで、をひと目で
    private func summary(dashboard: HomeDashboard, goal: WeightGoal?) -> some View {
        HStack(alignment: .top) {
            if let latest = entries.first {
                summaryItem("最新の体重", kg: latest.weightKg)
            }
            if let trendKg = dashboard.currentTrendKg {
                summaryItem("トレンド", kg: trendKg)
            }
            if let goal, let trendKg = dashboard.currentTrendKg {
                summaryItem("目標まで", kg: abs(goal.targetWeightKg - trendKg))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryItem(_ title: LocalizedStringKey, kg: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(kg, format: .number.precision(.fractionLength(1))) kg")
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("まだ記録がありません", systemImage: "chart.xyaxis.line")
        } description: {
            Text("体重を記録すると、ここにグラフと予測が表示されます。")
        } actions: {
            Button("体重を記録する") {
                isShowingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - プレビュー

/// プレビュー用：3 週間分、ゆるやかに減っている記録
@MainActor
private func homePreviewContainer(goalKg: Double = 62, deadlineMonths: Int = 3, isFlat: Bool = false) -> ModelContainer {
    let container = try! ModelContainer(
        for: WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    for daysAgo in 0..<21 {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        // 日々のブレを少し入れる
        let noise = [0.0, 0.3, -0.2, 0.1, -0.1, 0.2, -0.3][daysAgo % 7]
        let weightKg = (isFlat ? 65.0 : 64.0 + 0.05 * Double(daysAgo)) + noise
        context.insert(WeightEntry(date: date, weightKg: weightKg))
    }
    context.insert(UserProfile(heightCm: 170, birthYear: 1990, sex: .male, activityLevel: .light))
    let deadline = Calendar.current.date(byAdding: .month, value: deadlineMonths, to: .now)!
    let start = Calendar.current.date(byAdding: .day, value: -21, to: .now)!
    context.insert(WeightGoal(targetWeightKg: goalKg, deadline: deadline, startDate: start, startWeightKg: 65))
    return container
}

#Preview("順調") {
    HomeView()
        .modelContainer(homePreviewContainer())
}

#Preview("横ばい（食べ物ヒント）") {
    HomeView()
        .modelContainer(homePreviewContainer(isFlat: true))
}

#Preview("目標が速すぎる") {
    HomeView()
        .modelContainer(homePreviewContainer(goalKg: 55, deadlineMonths: 1))
}

#Preview("記録なし") {
    HomeView()
        .modelContainer(for: [WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self], inMemory: true)
}
