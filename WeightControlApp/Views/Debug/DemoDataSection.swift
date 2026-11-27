#if DEBUG
import SwiftUI
import SwiftData

/// 設定タブの「開発用：デモデータ」セクション。
///
/// `#if DEBUG` で囲んでいるので、Xcode から実行したとき（Debug ビルド）だけ表示され、
/// App Store に出すとき（Release ビルド）にはコードごと入りません。
///
/// ボタンを押すと、いまの記録・プロフィール・目標・運動スタンプをすべて消して、
/// 選んだシナリオのデモデータに置きかえます。画面に出るはずの値は `docs/DEMO_DATA.md` にまとめています。
struct DemoDataSection: View {
    @Environment(\.modelContext) private var modelContext
    /// 確認ダイアログを出しているシナリオ
    @State private var pendingScenario: DemoScenario?
    /// 最後に読み込んだシナリオ（読み込めたことを画面で伝えるため）
    @State private var loadedScenario: DemoScenario?

    var body: some View {
        Section {
            ForEach(DemoScenario.allCases) { scenario in
                Button {
                    pendingScenario = scenario
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scenario.title)
                        Text(scenario.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let loadedScenario {
                Label("「\(loadedScenario.title)」を読み込みました。ホームタブで確認してください。", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("開発用：デモデータ")
        } footer: {
            Text("今の記録・プロフィール・目標・運動スタンプ・チートデー・妊娠中モードの設定をすべて消して、デモデータに置きかえます。Debug ビルドだけに表示されます。")
        }
        .confirmationDialog(
            "今のデータを消して、デモデータを読み込みますか？",
            isPresented: Binding(
                get: { pendingScenario != nil },
                set: { if !$0 { pendingScenario = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingScenario
        ) { scenario in
            Button("消して読み込む", role: .destructive) {
                DemoDataLoader.replaceAll(with: scenario.dataSet(today: .now), in: modelContext)
                loadedScenario = scenario
            }
        } message: { scenario in
            Text(scenario.title)
        }
    }
}

/// デモデータを SwiftData に書き込む係（Debug ビルド専用）。
enum DemoDataLoader {
    /// 今のデータをすべて消して、`dataSet` の内容を保存します。
    static func replaceAll(with dataSet: DemoDataSet, in context: ModelContext) {
        deleteAll(WeightEntry.self, in: context)
        deleteAll(WeightGoal.self, in: context)
        deleteAll(ExerciseDay.self, in: context)
        deleteAll(CheatDay.self, in: context)
        deleteAll(PregnancyPlan.self, in: context)

        for point in dataSet.points {
            context.insert(WeightEntry(date: point.date, weightKg: point.weightKg))
        }
        for day in dataSet.exerciseDays {
            context.insert(ExerciseDay(date: day))
        }

        // プロフィールは消すと一瞬「はじめに」画面に切り替わってしまうので、あれば書きかえる
        let profile = dataSet.profile
        let sex = userProfileSex(profile.sex)
        let activity = userProfileActivity(profile.activityLevel)
        let existingProfiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if let current = existingProfiles.first {
            current.heightCm = profile.heightCm
            current.birthYear = profile.birthYear
            current.sex = sex
            current.activityLevel = activity
            // 計算方法は「自動」にそろえる（ヘルスケア連携がオフなら活動量で計算され、資料の値と一致する）
            current.energyMode = .automatic
            current.updatedAt = .now
            existingProfiles.dropFirst().forEach { context.delete($0) }
        } else {
            context.insert(UserProfile(heightCm: profile.heightCm, birthYear: profile.birthYear, sex: sex, activityLevel: activity))
        }

        context.insert(WeightGoal(
            targetWeightKg: dataSet.goal.targetWeightKg,
            deadline: dataSet.goal.deadline,
            startDate: dataSet.goalStartDate,
            startWeightKg: dataSet.goal.startWeightKg,
            maintenanceStartDate: dataSet.goal.maintenanceStartDate,
            maintenanceHalfWidthKg: dataSet.goal.maintenanceHalfWidthKg
        ))

        if let pregnancy = dataSet.pregnancy {
            context.insert(PregnancyPlan(
                dueDate: pregnancy.dueDate,
                prePregnancyWeightKg: pregnancy.prePregnancyWeightKg,
                startedAt: dataSet.goalStartDate.addingTimeInterval(60)
            ))
        }

        try? context.save()
    }

    /// 1 件ずつ消す（@Query の画面にすぐ反映されるように）
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in items {
            context.delete(item)
        }
    }

    /// 計算用の性別 → 保存用の性別
    private static func userProfileSex(_ sex: BiologicalSex) -> UserProfile.Sex {
        switch sex {
        case .male: .male
        case .female: .female
        }
    }

    /// 計算用の活動量 → 保存用の活動量
    private static func userProfileActivity(_ level: CalculatorActivityLevel) -> UserProfile.ActivityLevel {
        switch level {
        case .sedentary: .sedentary
        case .light: .light
        case .moderate: .moderate
        case .active: .active
        case .veryActive: .veryActive
        }
    }
}

#Preview {
    List {
        DemoDataSection()
    }
    .modelContainer(.preview())
}
#endif
