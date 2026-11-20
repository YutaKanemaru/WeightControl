import SwiftUI
import SwiftData

/// 「設定」タブの画面：プロフィールと目標の確認・変更、記録のリマインド通知。
struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    /// 目標は 1 件だけの想定。念のため新しい順に並べて先頭を使う。
    @Query(sort: \WeightGoal.startDate, order: .reverse) private var goals: [WeightGoal]
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    var body: some View {
        NavigationStack {
            List {
                profileSection
                energySection
                goalSection
                healthSection
                ReminderSettingsSection()

                Section {
                } footer: {
                    Text("このアプリは医療アドバイスではありません。体調に不安があるときは医師に相談してください。ご利用は自己責任でお願いします。")
                }

                #if DEBUG
                // 予測やカロリーの表示を確かめるためのデモデータ（Xcode から実行したときだけ表示）
                DemoDataSection()
                #endif
            }
            .navigationTitle("設定")
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section("プロフィール") {
            if let profile = profiles.first {
                let age = ProfileInputValidator.age(birthYear: profile.birthYear, on: .now)
                LabeledContent("身長") {
                    Text("\(profile.heightCm, format: .number.precision(.fractionLength(0...1))) cm")
                }
                LabeledContent("年齢") {
                    Text("\(age) 歳（\(profile.birthYear.formatted(.number.grouping(.never))) 年生まれ）")
                }
                LabeledContent("性別") {
                    Text(profile.sex.title)
                }
                LabeledContent("活動量") {
                    Text(profile.activityLevel.title)
                }
                NavigationLink("プロフィールを編集") {
                    EditProfileView(profile: profile)
                }
            }
        }
    }

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

    private var healthSection: some View {
        Section("連携") {
            NavigationLink {
                HealthSettingsView()
            } label: {
                Label("Apple ヘルスケア", systemImage: "heart.fill")
            }
        }
    }

    private var goalSection: some View {
        Section("目標") {
            if let goal = goals.first {
                LabeledContent("目標体重") {
                    Text("\(goal.targetWeightKg, format: .number.precision(.fractionLength(1))) kg")
                }
                LabeledContent("期限") {
                    Text(goal.deadline, format: .dateTime.year().month().day())
                }
                NavigationLink("目標を変更") {
                    EditGoalView(goal: goal, currentWeightKg: entries.first?.weightKg)
                }
            } else {
                NavigationLink("目標を決める") {
                    EditGoalView(goal: nil, currentWeightKg: entries.first?.weightKg)
                }
            }
        }
    }
}

#Preview("目標あり") {
    SettingsView()
        .modelContainer(.preview())
}

#Preview("目標なし") {
    SettingsView()
        .modelContainer(.preview(includesGoal: false))
}
