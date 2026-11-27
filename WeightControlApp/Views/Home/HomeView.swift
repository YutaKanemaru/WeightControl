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
    /// 決めたチートデー（Pro）。提案の「週 2 日まで」と、今日がチートデーかの判断に使う。
    @Query(sort: \CheatDay.date) private var cheatDays: [CheatDay]
    /// 妊娠中モード（docs/PREGNANCY_MODE.md）。モード中は、減量のための機能をすべて止めて、増え方の目安を出す
    @Query(sort: \PregnancyPlan.startedAt, order: .reverse) private var pregnancyPlans: [PregnancyPlan]
    @AppStorage(PregnancyPreferenceKey.resumedGoalEndedAt) private var resumedGoalEndedAt = 0.0
    @AppStorage(PregnancyPreferenceKey.checkInDismissedDueDate) private var checkInDismissedDueDate = 0.0

    /// ヘルスケア連携の係。連携していて運動データがあれば、消費カロリーの計算に実績を使う。
    @Environment(HealthSyncController.self) private var health: HealthSyncController?
    /// Pro を使えるか。使えないときは、Pro のカードを「ぼかして」出す（docs/PRO.md）
    @Environment(ProAccess.self) private var pro: ProAccess?
    /// ホームの「1 か月無料で試せます」のカードを閉じたか
    @AppStorage(ProPreferenceKey.trialOfferDismissed) private var isTrialOfferDismissed = false

    @State private var isShowingAddSheet = false

    /// 食品カロリー表（アプリに同梱の JSON）。一度だけ読み込む。読めなければ空にして、ヒントを出さないだけにする。
    private static let foods: [FoodItem] = (try? FoodCatalog.loadBundledFoods()) ?? []

    var body: some View {
        let pregnancyState = PregnancyModeResolver.state(
            plans: pregnancyPlans, profile: profiles.first, goal: goals.first, resumedEndedAt: resumedGoalEndedAt
        )
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if pregnancyState == .active, let plan = pregnancyPlans.activePlan {
                        pregnancyContent(plan: plan)
                    } else {
                        regularContent(usesGoal: pregnancyState.usesGoal)
                    }
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
                AddWeightEntryView(
                    lastWeightKg: entries.first?.weightKg,
                    lastEntryDate: entries.first?.date,
                    existingDates: entries.map(\.date)
                )
            }
        }
    }

    // MARK: - 妊娠中モード

    /// 妊娠中モードのホーム。目標・予測・カロリー・チートデー・キープモード・食べ物ヒントは出さない。
    @ViewBuilder
    private func pregnancyContent(plan: PregnancyPlan) -> some View {
        let points = entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) }
        let dashboard = plan.dashboard(points: points, heightCm: profiles.first?.heightCm ?? 0)
        let start = GestationalAgeCalculator.startDate(dueDate: plan.dueDate)
        let measured = WeightTrendCalculator.dailyAverages(points.filter { $0.date >= start })

        if dashboard.isPastDueCheckIn, checkInDismissedDueDate != plan.dueDate.timeIntervalSinceReferenceDate {
            PregnancyCheckInCard(plan: plan) {
                checkInDismissedDueDate = plan.dueDate.timeIntervalSinceReferenceDate
            }
        }

        PregnancySummaryCard(dashboard: dashboard, latestDate: entries.first?.date)

        if entries.isEmpty {
            EmptyRecordsCard { isShowingAddSheet = true }
        } else {
            PregnancyPraiseCard(streakDays: dashboard.streakDays, recentRecordedDays: dashboard.recentRecordedDays)
        }

        PregnancyChartCard(dashboard: dashboard, measured: measured, dueDate: plan.dueDate)
        PregnancyStatusCard(dashboard: dashboard)
        PregnancyNutritionCard(trimester: dashboard.age.trimester)
        PregnancyDisclaimerText()
    }

    // MARK: - ふだんのホーム

    /// - Parameter usesGoal: 目標を使うか（妊娠中モードを終えたあと、前の目標を一時停止しているときは false）
    @ViewBuilder
    private func regularContent(usesGoal: Bool) -> some View {
        let storedGoal = goals.first
        let goal = usesGoal ? storedGoal : nil
        let proStatus = pro?.status() ?? .trialAvailable
        let isProUnlocked = proStatus.isUnlocked
        // Pro の計算はいつも行い、使えないときは画面でぼかす（「提案があります」のように、項目があることは見せるため）。
        // 無料版の結果（予測・カロリーなど）は、これで変わることはありません。
        let dashboard = HomeDashboardBuilder.build(
            points: entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) },
            profile: profiles.first?.dashboardProfile,
            // キープモードは、Pro を使えるときだけモードとして計算する（お試しが終わったら、ふだんの目標の画面に戻る）
            goal: goal?.dashboardGoal(includesMaintenance: isProUnlocked),
            foods: Self.foods,
            healthActivity: health?.activitySummary,
            includesPro: true,
            cheatDays: cheatDays.map(\.date),
            now: .now
        )

                    if let storedGoal, !usesGoal {
                        PregnancyEndedGoalCard(goal: storedGoal, currentWeightKg: entries.first?.weightKg) {
                            resumedGoalEndedAt = PregnancyModeResolver.lastEndedAtValue(plans: pregnancyPlans)
                        }
                    }

                    if ProTrialCard.isVisible(status: proStatus, isOfferDismissed: isTrialOfferDismissed) {
                        ProTrialCard(status: proStatus)
                    }

                    if let latest = entries.first {
                        WeightSummaryCard(
                            latestKg: latest.weightKg,
                            latestDate: latest.date,
                            goalDistance: goalDistance(latestKg: latest.weightKg, goal: goal),
                            goalWeightKg: goal?.targetWeightKg,
                            maintenanceRange: dashboard.maintenance?.range
                        )

                        PraiseCard(message: dashboard.praise, streakDays: dashboard.streakDays)

                        WeightChartCard(
                            dashboard: dashboard,
                            goalWeightKg: goal?.targetWeightKg,
                            deadline: goal?.deadline,
                            isProUnlocked: isProUnlocked
                        )
                    } else {
                        EmptyRecordsCard { isShowingAddSheet = true }
                    }

                    if let goal, let maintenance = dashboard.maintenance {
                        // キープモード中：達成の見込み・修正案・見込みの幅の代わりに、範囲のカード
                        MaintenanceStatusCard(result: maintenance, goal: goal, currentWeightKg: entries.first?.weightKg)
                        if let goalBMI = dashboard.goalBMI, goalBMI.needsHomeAttention {
                            GoalBMICard(advice: goalBMI, goal: goal, currentWeightKg: entries.first?.weightKg)
                        }
                    } else if let goal {
                        if dashboard.isGoalAchieved {
                            GoalAchievedCard(goal: goal, isProUnlocked: isProUnlocked)
                        }
                        if !entries.isEmpty, let forecast = dashboard.forecast {
                            ForecastCard(forecast: forecast, isProUnlocked: isProUnlocked)
                        }
                        if case .available(let range)? = dashboard.forecastRange {
                            if isProUnlocked {
                                ForecastRangeCard(range: range)
                            } else {
                                LockedForecastRangeCard()
                            }
                        }
                        if case .tooAggressive(let correction)? = dashboard.safety {
                            GoalCorrectionCard(correction: correction, goal: goal, currentWeightKg: entries.first?.weightKg)
                        }
                        if let goalBMI = dashboard.goalBMI, goalBMI.needsHomeAttention {
                            GoalBMICard(advice: goalBMI, goal: goal, currentWeightKg: entries.first?.weightKg)
                        }
                    } else if usesGoal {
                        GoalPromptCard(currentWeightKg: entries.first?.weightKg)
                    }

                    // 妊娠中モードを終えたあと、目標を一時停止している間は、カロリーの目安も出さない
                    if usesGoal, let intake = dashboard.intake {
                        IntakeCard(
                            intake: intake,
                            energyChoice: dashboard.energyChoice,
                            isCheatDay: isProUnlocked && dashboard.isCheatDayToday,
                            maintenanceStatus: dashboard.maintenance?.status
                        )
                        let suggestion = dashboard.cheatDaySuggestion?.suggestion
                        // キープモード中はチートデーを出さない（目標に向かって進むための機能なので）
                        if dashboard.maintenance == nil {
                            if isProUnlocked {
                                if CheatDayCard.isVisible(suggestion: suggestion, cheatDays: cheatDays) {
                                    CheatDayCard(suggestion: suggestion, cheatDays: cheatDays, maintenanceKcal: intake.tdeeKcal)
                                }
                            } else if suggestion != nil {
                                // 提案できるときだけ、ぼかしたカードで「提案があります」と知らせる
                                LockedCheatDayCard()
                            }
                        }
                    }

                    if usesGoal, let phrase = dashboard.calorieHint?.foodPhrase, let overPlan = dashboard.overPlanKcalPerDay {
                        FoodHintCard(foodPhrase: phrase, overPlanKcalPerDay: overPlan)
                    }

                    Text("予測やカロリーは一般的な計算式による目安です。このアプリは医療アドバイスではありません。体調に不安があるときは医師に相談してください。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「目標まで」。目標がなければ nil。
    ///
    /// カードの大きな数字（最新の体重）と同じ基準にするため、測った体重そのものから計算します
    /// （docs/WEIGHT_RECORDS.md）。予報やカロリーは、今までどおり直線の今日の値（`dashboard.currentWeightKg`）を使います。
    /// 目標の向きは、目標を決めたときの体重（なければいちばん古い記録）で決めます。
    private func goalDistance(latestKg: Double, goal: WeightGoal?) -> GoalDistance? {
        guard let goal else { return nil }
        return GoalDistanceCalculator.distance(
            latestKg: latestKg,
            targetKg: goal.targetWeightKg,
            startKg: goal.startWeightKg ?? entries.last?.weightKg
        )
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
        for: WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self, CheatDay.self, PregnancyPlan.self,
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

#Preview("Pro（見込みの幅・チートデーの提案）") {
    HomeView()
        .modelContainer(homePreviewContainer())
        .environment(ProAccess.previewUnlocked())
}

#Preview("お試し終了（Pro の中身をぼかす）") {
    HomeView()
        .modelContainer(homePreviewContainer())
        .environment(ProAccess.previewTrialEnded())
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

#Preview("妊娠中モード") {
    let container = homePreviewContainer(goalKg: 62)
    let context = container.mainContext
    let profile = try! context.fetch(FetchDescriptor<UserProfile>()).first!
    profile.sex = .female
    profile.heightCm = 160
    context.insert(PregnancyPlan(dueDate: Calendar.current.date(byAdding: .day, value: 120, to: .now)!, prePregnancyWeightKg: 60))
    return HomeView()
        .modelContainer(container)
}

#Preview("妊娠中モードを終えたあと（目標を一時停止）") {
    let container = homePreviewContainer(goalKg: 62)
    let context = container.mainContext
    let profile = try! context.fetch(FetchDescriptor<UserProfile>()).first!
    profile.sex = .female
    context.insert(PregnancyPlan(dueDate: .now, prePregnancyWeightKg: 60, startedAt: .distantPast, endedAt: .now))
    return HomeView()
        .modelContainer(container)
}

#Preview("キープモード（Pro）") {
    let container = homePreviewContainer(goalKg: 64)
    let goal = try! container.mainContext.fetch(FetchDescriptor<WeightGoal>()).first!
    goal.maintenanceStartDate = Calendar.current.date(byAdding: .day, value: -14, to: .now)
    return HomeView()
        .modelContainer(container)
        .environment(ProAccess.previewUnlocked())
}

#Preview("目標達成（無料版の Pro 案内）") {
    HomeView()
        .modelContainer(homePreviewContainer(goalKg: 64))
}

#Preview("目標なし") {
    HomeView()
        .modelContainer(homePreviewContainer(goalKg: nil))
}

#Preview("記録なし") {
    HomeView()
        .modelContainer(for: [WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self, CheatDay.self, PregnancyPlan.self], inMemory: true)
}

#Preview("記録なし・ダークモード") {
    HomeView()
        .modelContainer(for: [WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self, CheatDay.self, PregnancyPlan.self], inMemory: true)
        .preferredColorScheme(.dark)
}
