import SwiftUI
import SwiftData

/// 「記録」タブの画面：体重の履歴一覧。
///
/// - いちばん上に「最新の体重」を大きく出し、その下に月ごとの一覧を並べます。
/// - 前回からの増減は、矢印（SF Symbols）と色で見せます。目標の向きに動いたときだけ緑にし、
///   それ以外はグレーのまま。体重は毎日上下するのがふつうなので、増えても赤や警告にはしません。
///   （どの色にするかの判断は `Logic/History/WeightChangeStyle` にあります）
/// - `@Query` が SwiftData から記録を読み出し、データが増えたり消えたりすると画面を自動で描き直します。
/// - 右上の「＋」で入力画面（`AddWeightEntryView`）をシート（下から出てくる画面）で開きます。
/// - 行を左にスワイプするか、「編集」ボタンから記録を削除できます。
struct WeightHistoryView: View {
    /// 保存・削除の窓口。アプリ全体で 1 つの「データベースへの接続」を共有しています。
    @Environment(\.modelContext) private var modelContext
    /// ヘルスケア連携の係（プレビューなどで渡されていないときは nil）
    @Environment(HealthSyncController.self) private var health: HealthSyncController?

    /// 体重の記録を「日付の新しい順」で取り出す。
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    /// 目標（増減の色づけに、減らしたいのか増やしたいのかを使う）。1 件だけの想定なので新しい順の先頭を使う。
    @Query(sort: \WeightGoal.startDate, order: .reverse) private var goals: [WeightGoal]
    /// 妊娠中モードの間は、増えても減ってもグレーにする（「増えた＝悪い」と見せないため。docs/PREGNANCY_MODE.md）
    @Query private var pregnancyPlans: [PregnancyPlan]
    @Query private var profiles: [UserProfile]
    @AppStorage(PregnancyPreferenceKey.resumedGoalEndedAt) private var resumedGoalEndedAt = 0.0

    /// 入力画面を出しているかどうか。`@State` は「この画面が覚えておく値」です。
    @State private var isShowingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("体重の記録")
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
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

    /// まだ 1 件も記録がないときの表示
    private var emptyState: some View {
        ContentUnavailableView {
            Label("まだ記録がありません", systemImage: "scalemass")
        } description: {
            Text("体重計に乗ったら、数字を入れるだけ。記録はこの端末の中だけに保存されます。")
        } actions: {
            Button("最初の体重を記録する") {
                isShowingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// 記録の一覧
    private var historyList: some View {
        // 計算は Logic 側に任せ、画面は結果を並べるだけにする
        let changes = WeightChangeCalculator.changesFromPrevious(
            entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) }
        )
        let sections = WeightHistorySections.byMonth(entries.map(\.date))
        let direction = goalDirection

        return List {
            if let latest = entries.first {
                Section {
                    LatestWeightSummary(
                        entry: latest,
                        style: WeightChangeStyle.classify(changeKg: changes[0], direction: direction),
                        changeKg: changes[0],
                        recordCount: entries.count
                    )
                }
            }

            ForEach(sections, id: \.monthStart) { section in
                Section {
                    ForEach(section.indices, id: \.self) { index in
                        WeightEntryRow(
                            entry: entries[index],
                            changeKg: changes[index],
                            style: WeightChangeStyle.classify(changeKg: changes[index], direction: direction)
                        )
                    }
                    .onDelete { offsets in
                        // セクションの中での位置を、全体の一覧での位置に読みかえて削除する
                        deleteEntries(at: offsets.map { section.indices[$0] })
                    }
                } header: {
                    Text(section.monthStart, format: .dateTime.year().month(.wide))
                }
            }
        }
    }

    /// 目標の向き。目標がなければ nil（増減に色を付けない）。
    private var goalDirection: GoalDirection? {
        guard let goal = goals.first else { return nil }
        let pregnancyState = PregnancyModeResolver.state(
            plans: pregnancyPlans, profile: profiles.first, goal: goal, resumedEndedAt: resumedGoalEndedAt
        )
        guard pregnancyState.usesGoal else { return nil }
        // 目標を決めたときの体重がなければ、いちばん古い記録をスタートとみなす（ホームと同じ考え方）
        guard let startKg = goal.startWeightKg ?? entries.last?.weightKg else { return nil }
        return HomeDashboardBuilder.goalDirection(startKg: startKg, targetKg: goal.targetWeightKg)
    }

    /// 選ばれた行（全体の一覧での位置）の記録を削除する
    private func deleteEntries(at indices: [Int]) {
        // 先に対象を取り出しておく（削除すると `entries` の並びが変わるため）
        let targets = indices.map { entries[$0] }
        withAnimation {
            for entry in targets {
                // このアプリがヘルスケアに書き込んだ記録なら、ヘルスケアからも消す
                health?.removeFromHealthIfNeeded(entry)
                modelContext.delete(entry)
            }
        }
    }
}

// MARK: - 部品

/// 一覧のいちばん上：最新の体重を大きく
private struct LatestWeightSummary: View {
    let entry: WeightEntry
    let style: WeightChangeStyle?
    let changeKg: Double?
    let recordCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetricView(
                "最新の体重",
                value: entry.weightKg,
                unit: "kg",
                caption: Text(entry.date, format: .dateTime.month().day().weekday().hour().minute()),
                size: .hero
            )
            // 大きい文字のときは横に並べると窮屈なので、縦に並べ直す
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { details }
                VStack(alignment: .leading, spacing: 4) { details }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var details: some View {
        if let changeKg, let style {
            WeightChangeLabel(changeKg: changeKg, style: style, prefix: "前回から")
        }
        Label("記録 \(recordCount) 回", systemImage: "checkmark.seal")
            .foregroundStyle(.secondary)
    }
}

/// 一覧の 1 行分：日付・体重・前回からの増減
struct WeightEntryRow: View {
    let entry: WeightEntry
    /// 前回の記録からの増減（kg）。最初の記録は nil。
    let changeKg: Double?
    /// 増減の見せかた。最初の記録は nil。
    let style: WeightChangeStyle?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date, format: .dateTime.day().weekday())
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(entry.date, format: .dateTime.hour().minute())
                    if entry.importedFromHealthKit {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .accessibilityLabel("ヘルスケアから取り込み")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(entry.weightKg, format: .number.precision(.fractionLength(1)))
                        .font(.title2)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .monospacedDigit()
                    Text("kg")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let changeKg, let style {
                    WeightChangeLabel(changeKg: changeKg, style: style)
                        .font(.caption)
                } else {
                    Text("はじめての記録")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // VoiceOver では 1 行をまとめて「20日 金曜日、7:30、64.5 kg、0.3 kg 減」のように読み上げる
        .accessibilityElement(children: .combine)
    }
}

/// 「↘ −0.3 kg」のような増減の表示。目標の向きなら緑、それ以外はグレー。
struct WeightChangeLabel: View {
    let changeKg: Double
    let style: WeightChangeStyle
    /// 前に付ける言葉（例:「前回から」）
    var prefix: LocalizedStringKey?

    var body: some View {
        // -0.0 を 0.0 として表示するため、0 のときは 0 に置き換える
        let value = changeKg == 0 ? 0 : changeKg
        HStack(spacing: 4) {
            if let prefix {
                Text(prefix)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: systemImage)
                .fontWeight(.semibold)
            Text("\(value, format: .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))) kg")
                .monospacedDigit()
        }
        .foregroundStyle(style.isTowardGoal ? Color.green : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// 矢印の SF Symbols
    private var systemImage: String {
        switch style.movement {
        case .down: "arrow.down.right"
        case .up: "arrow.up.right"
        case .steady: "equal"
        }
    }

    /// VoiceOver の読み上げ（記号の「−」や矢印は読み上げにくいので、言葉にする）
    private var accessibilityText: Text {
        let amount = abs(changeKg).formatted(.number.precision(.fractionLength(1)))
        let change: Text = switch style.movement {
        case .down: Text("\(amount) kg 減")
        case .up: Text("\(amount) kg 増")
        case .steady: Text("変わらず")
        }
        guard let prefix else { return change }
        return Text("\(Text(prefix)) \(change)")
    }
}

// MARK: - プレビュー

/// プレビュー用の記録。`days` 日分（ひと月をまたぐ長さ）、ゆるやかに減りつつ日々上下する。
@MainActor
private func historyPreviewContainer(days: Int = 40, goalKg: Double? = 62) -> ModelContainer {
    let container = try! ModelContainer(
        for: WeightEntry.self, UserProfile.self, WeightGoal.self, ExerciseDay.self, PregnancyPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    for daysAgo in 0..<days {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let noise = [0.0, 0.3, -0.2, 0.1, -0.1, 0.2, -0.3][daysAgo % 7]
        context.insert(WeightEntry(
            date: date,
            weightKg: 64.0 + 0.04 * Double(daysAgo) + noise,
            importedFromHealthKit: daysAgo % 5 == 0
        ))
    }
    if let goalKg {
        let deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now)!
        context.insert(WeightGoal(targetWeightKg: goalKg, deadline: deadline, startWeightKg: 66))
    }
    return container
}

#Preview("記録あり") {
    WeightHistoryView()
        .modelContainer(historyPreviewContainer())
}

#Preview("記録あり・ダークモード") {
    WeightHistoryView()
        .modelContainer(historyPreviewContainer())
        .preferredColorScheme(.dark)
}

#Preview("記録あり・大きい文字") {
    WeightHistoryView()
        .modelContainer(historyPreviewContainer())
        .dynamicTypeSize(.accessibility3)
}

#Preview("目標なし（色を付けない）") {
    WeightHistoryView()
        .modelContainer(historyPreviewContainer(goalKg: nil))
}

#Preview("記録 1 件") {
    WeightHistoryView()
        .modelContainer(historyPreviewContainer(days: 1))
}

#Preview("記録なし") {
    WeightHistoryView()
        .modelContainer(for: [WeightEntry.self, WeightGoal.self, UserProfile.self, PregnancyPlan.self], inMemory: true)
}

#Preview("記録なし・ダークモード") {
    WeightHistoryView()
        .modelContainer(for: [WeightEntry.self, WeightGoal.self, UserProfile.self, PregnancyPlan.self], inMemory: true)
        .preferredColorScheme(.dark)
}
