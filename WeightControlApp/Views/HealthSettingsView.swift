import SwiftUI
import SwiftData

/// 設定タブの「Apple ヘルスケア連携」の画面。
///
/// - 連携のオン・オフ（オンにすると、ヘルスケアへのアクセス許可を求める画面が出ます）
/// - アプリで入力した体重を、ヘルスケアにも書き込むか
/// - 今すぐ同期するボタンと、最後に同期した結果
/// - ヘルスケアの歩数・運動時間から見た「活動量」の目安と、1 日の消費カロリーの目安
struct HealthSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthSyncController.self) private var health: HealthSyncController?

    @Query private var profiles: [UserProfile]
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    var body: some View {
        List {
            if let health, health.isAvailable {
                connectionSection(health)
                if health.isEnabled {
                    syncSection(health)
                    activitySection(health)
                }
            } else {
                // 空の状態：ヘルスケアを使えない端末
                ContentUnavailableView(
                    "ヘルスケアを使えません",
                    systemImage: "heart.slash",
                    description: Text("この端末にはヘルスケアがありません。体重の記録やカレンダーは、このまま使えます。")
                )
            }

            Section {
            } footer: {
                DisclaimerFooter()
            }
        }
        .navigationTitle("ヘルスケア連携")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - オン・オフ

    private func connectionSection(_ health: HealthSyncController) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { health.isEnabled },
                set: { isOn in
                    if isOn {
                        Task { await health.enable(context: modelContext) }
                    } else {
                        health.disable()
                    }
                }
            )) {
                Label("ヘルスケアと連携する", systemImage: "heart.text.square")
            }
            if health.isEnabled {
                Toggle(isOn: Binding(
                    get: { health.writesWeightToHealth },
                    set: { health.writesWeightToHealth = $0 }
                )) {
                    Label("体重をヘルスケアにも書き込む", systemImage: "square.and.arrow.down")
                }
            }
        } footer: {
            Text("ヘルスケアの体重を取り込み、歩数・エクササイズ・ワークアウトから運動した日にスタンプを押します。データは端末の中だけで使い、外部には送りません。読み取る項目は「設定」アプリ →「ヘルスケア」→「データアクセスとデバイス」から変更できます。")
        }
    }

    // MARK: - 同期

    private func syncSection(_ health: HealthSyncController) -> some View {
        Section("同期") {
            Button {
                Task { await health.sync(context: modelContext) }
            } label: {
                HStack {
                    Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if health.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(health.isSyncing)

            switch health.status {
            case .idle, .syncing:
                EmptyView()
            case .finished(let date, let importedCount):
                LabeledContent("最後の同期") {
                    Text(date, format: .dateTime.hour().minute())
                }
                if importedCount > 0 {
                    NoticeLabel(text: Text("体重の記録を \(importedCount) 件取り込みました。"), style: .success)
                }
            case .failed(let message):
                NoticeLabel(text: Text(message), style: .caution)
            }
        }
    }

    // MARK: - 活動量の目安

    @ViewBuilder
    private func activitySection(_ health: HealthSyncController) -> some View {
        Section {
            if let summary = health.activitySummary {
                LabeledContent("1 日の平均歩数") {
                    Text("\(summary.averageSteps, format: .number.precision(.fractionLength(0))) 歩")
                }
                LabeledContent("1 日の平均運動時間") {
                    Text("\(summary.averageActiveMinutes, format: .number.precision(.fractionLength(0))) 分")
                }
                LabeledContent("1 日の平均アクティブエネルギー") {
                    Text("\(summary.averageActiveEnergyKcal, format: .number.precision(.fractionLength(0))) kcal")
                }
                if let tdee = estimatedDailyEnergyKcal(summary) {
                    LabeledContent("1 日の消費カロリーの目安") {
                        Text("\(tdee, format: .number.precision(.fractionLength(0))) kcal")
                    }
                }
                if let profile = profiles.first,
                   let suggested = UserProfile.ActivityLevel(rawValue: summary.suggestedLevel.rawValue) {
                    LabeledContent("実績から見た活動量") {
                        Text(suggested.title)
                    }
                    if profile.activityLevel != suggested {
                        Button {
                            profile.activityLevel = suggested
                            profile.updatedAt = .now
                        } label: {
                            Text("プロフィールの活動量を「\(Text(suggested.title))」にする")
                        }
                    }
                }
            } else {
                NoticeLabel("運動量のデータがまだ少ないため、目安を出せません。7 日分ほど集まると表示されます。")
            }
        } header: {
            Text("直近 \(HealthSyncController.activitySummaryDays) 日の運動量")
        } footer: {
            Text("消費カロリーの目安は、基礎代謝（身長・体重・年齢・性別から計算）にヘルスケアのアクティブエネルギーを足して出しています。")
        }
    }

    /// 1 日の消費カロリーの目安（kcal）。計算は Logic の `CalorieCalculator` に任せます。
    private func estimatedDailyEnergyKcal(_ summary: ActivitySummary) -> Double? {
        guard let profile = profiles.first,
              let weightKg = entries.first?.weightKg,
              let sex = BiologicalSex(rawValue: profile.sex.rawValue) else { return nil }
        let bmr = CalorieCalculator.basalMetabolicRate(
            weightKg: weightKg,
            heightCm: profile.heightCm,
            ageYears: CalorieCalculator.ageYears(birthYear: profile.birthYear, on: .now),
            sex: sex
        )
        return CalorieCalculator.totalDailyEnergyExpenditure(
            bmrKcal: bmr,
            averageActiveEnergyKcal: summary.averageActiveEnergyKcal
        )
    }
}

#Preview {
    NavigationStack {
        HealthSettingsView()
    }
    .modelContainer(.preview())
    .environment(HealthSyncController())
}

#Preview("大きい文字・ダークモード") {
    NavigationStack {
        HealthSettingsView()
    }
    .modelContainer(.preview())
    .environment(HealthSyncController())
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}
