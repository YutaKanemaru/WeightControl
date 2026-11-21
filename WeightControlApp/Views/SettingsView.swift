import SwiftUI
import SwiftData

/// 「設定」タブの画面：目標・プロフィール・消費カロリーの計算・通知・ヘルスケア連携・ご利用にあたって。
///
/// iPhone の「設定」アプリと同じ標準の `List`（ひとまとまりごとの Section）を使い、
/// いちばん大事な「目標」だけは数字を大きく見せています。
/// 並び順は「よく見る・よく変えるもの」が上です。
struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    /// 目標は 1 件だけの想定。念のため新しい順に並べて先頭を使う。
    @Query(sort: \WeightGoal.startDate, order: .reverse) private var goals: [WeightGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    /// ヘルスケア連携の係（連携のオン・オフを行の右に出すため。プレビューでは nil のことがある）
    @Environment(HealthSyncController.self) private var health: HealthSyncController?

    var body: some View {
        NavigationStack {
            List {
                goalSection
                profileSection
                energySection
                ReminderSettingsSection()
                healthSection
                aboutSection

                #if DEBUG
                // 予測やカロリーの表示を確かめるためのデモデータ（Xcode から実行したときだけ表示）
                DemoDataSection()
                #endif
            }
            .navigationTitle("設定")
        }
    }

    // MARK: - 目標

    @ViewBuilder
    private var goalSection: some View {
        Section {
            if let goal = goals.first {
                NavigationLink {
                    EditGoalView(goal: goal, currentWeightKg: entries.first?.weightKg)
                } label: {
                    goalSummary(goal)
                }
                .accessibilityHint(Text("目標を変更します"))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("目標はまだ決めていません", systemImage: "flag")
                        .font(.headline)
                    Text("目標体重と期限を決めると、届く日の予測や、1 日の食事の目安が出せます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)

                NavigationLink {
                    EditGoalView(goal: nil, currentWeightKg: entries.first?.weightKg)
                } label: {
                    Label("目標を決める", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("目標")
        }
    }

    /// 目標体重と、期限までの日数を大きく並べる
    private func goalSummary(_ goal: WeightGoal) -> some View {
        let daysLeft = GoalPlanAdvisor.daysLeft(until: goal.deadline, now: .now)
        let deadlineText = Text(goal.deadline, format: .dateTime.year().month().day())

        return ViewThatFits(in: .horizontal) {
            // ふつうの文字サイズ：横に 2 つ並べる
            HStack(alignment: .top, spacing: 24) {
                targetMetric(goal)
                deadlineMetric(daysLeft: daysLeft, deadlineText: deadlineText)
            }
            // 大きい文字で横に入らないとき：縦に並べる
            VStack(alignment: .leading, spacing: 12) {
                targetMetric(goal)
                deadlineMetric(daysLeft: daysLeft, deadlineText: deadlineText)
            }
        }
        .padding(.vertical, 4)
    }

    private func targetMetric(_ goal: WeightGoal) -> some View {
        MetricView("目標体重", value: goal.targetWeightKg, unit: "kg", size: .medium)
    }

    @ViewBuilder
    private func deadlineMetric(daysLeft: Int, deadlineText: Text) -> some View {
        if daysLeft > 0 {
            MetricView(
                "期限まで",
                value: Double(daysLeft),
                fractionLength: 0,
                unit: "日",
                caption: deadlineText,
                size: .medium
            )
        } else {
            MetricView(
                "期限",
                text: deadlineText,
                caption: Text("期限になりました。新しい期限を決めましょう。"),
                size: .medium
            )
        }
    }

    // MARK: - プロフィール

    @ViewBuilder
    private var profileSection: some View {
        Section {
            if let profile = profiles.first {
                let age = ProfileInputValidator.age(birthYear: profile.birthYear, on: .now)
                LabeledContent {
                    Text("\(profile.heightCm, format: .number.precision(.fractionLength(0...1))) cm")
                        .monospacedDigit()
                } label: {
                    Label("身長", systemImage: "ruler")
                }
                LabeledContent {
                    Text("\(age) 歳")
                        .monospacedDigit()
                } label: {
                    Label("年齢", systemImage: "calendar")
                }
                LabeledContent {
                    Text(profile.sex.title)
                } label: {
                    Label("性別", systemImage: "person")
                }
                LabeledContent {
                    Text(profile.activityLevel.title)
                } label: {
                    Label("活動量", systemImage: "figure.walk")
                }
                NavigationLink {
                    EditProfileView(profile: profile)
                } label: {
                    Label("プロフィールを編集", systemImage: "pencil")
                }
            } else {
                // ふつうは初回設定で作られるので出ないが、念のため
                NoticeLabel("プロフィールがまだありません。")
            }
        } header: {
            Text("プロフィール")
        } footer: {
            Text("身長・年齢・性別は、基礎代謝（何もしなくても使うカロリー）の計算に使います。")
        }
    }

    // MARK: - 消費カロリー

    /// 消費カロリーの計算方法（ホームの「1 日の摂取カロリーの目安」に使う）
    @ViewBuilder
    private var energySection: some View {
        if let profile = profiles.first {
            Section {
                EnergyModePicker(profile: profile)
            } header: {
                Text("消費カロリー")
            } footer: {
                Text(profile.energyMode.detail)
            }
        }
    }

    // MARK: - 連携

    private var healthSection: some View {
        Section("連携") {
            NavigationLink {
                HealthSettingsView()
            } label: {
                LabeledContent {
                    if let health, health.isAvailable {
                        health.isEnabled ? Text("オン") : Text("オフ")
                    }
                } label: {
                    Label("Apple ヘルスケア", systemImage: "heart.text.square")
                }
            }
        }
    }

    // MARK: - ご利用にあたって

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutAppView()
            } label: {
                Label("ご利用にあたって", systemImage: "info.circle")
            }
        } footer: {
            DisclaimerFooter()
        }
    }
}

#Preview("目標あり") {
    SettingsView()
        .modelContainer(.preview())
        .environment(HealthSyncController())
}

#Preview("目標なし") {
    SettingsView()
        .modelContainer(.preview(includesGoal: false))
}

#Preview("大きい文字・ダークモード") {
    SettingsView()
        .modelContainer(.preview())
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
