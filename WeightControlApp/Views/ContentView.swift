import SwiftUI
import SwiftData

/// アプリの最初の画面：体重の履歴一覧。
///
/// - `@Query` が SwiftData から記録を読み出し、データが増えたり消えたりすると画面を自動で描き直します。
/// - 右上の「＋」で入力画面（`AddWeightEntryView`）をシート（下から出てくる画面）で開きます。
/// - 行を左にスワイプするか、「編集」ボタンから記録を削除できます。
struct ContentView: View {
    /// 保存・削除の窓口。アプリ全体で 1 つの「データベースへの接続」を共有しています。
    @Environment(\.modelContext) private var modelContext

    /// 体重の記録を「日付の新しい順」で取り出す。
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

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
                AddWeightEntryView(lastWeightKg: entries.first?.weightKg)
            }
        }
    }

    /// まだ 1 件も記録がないときの表示
    private var emptyState: some View {
        ContentUnavailableView {
            Label("まだ記録がありません", systemImage: "scalemass")
        } description: {
            Text("今日の体重を記録して、はじめの一歩を踏み出しましょう。")
        } actions: {
            Button("体重を記録する") {
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

        return List {
            ForEach(Array(zip(entries, changes)), id: \.0.id) { pair in
                WeightEntryRow(entry: pair.0, changeKg: pair.1)
            }
            .onDelete(perform: deleteEntries)
        }
    }

    /// 一覧で選ばれた行（offsets）の記録を削除する
    private func deleteEntries(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(entries[index])
            }
        }
    }
}

/// 一覧の 1 行分：日付・体重・前回からの増減
struct WeightEntryRow: View {
    let entry: WeightEntry
    /// 前回の記録からの増減（kg）。最初の記録は nil。
    let changeKg: Double?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date, format: .dateTime.year().month().day().weekday())
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.weightKg, format: .number.precision(.fractionLength(1))) kg")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                if let changeKg {
                    // -0.0 を 0.0 として表示するため、0 のときは 0 に置き換える
                    let value = changeKg == 0 ? 0 : changeKg
                    Text("\(value, format: .number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))) kg")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("記録あり") {
    // プレビュー専用：メモリ上だけの一時的なデータベースにサンプルを入れる
    let container = try! ModelContainer(
        for: WeightEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let samples: [Double] = [65.0, 64.8, 64.9, 64.6, 64.5]
    for (daysAgo, weightKg) in samples.reversed().enumerated() {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        container.mainContext.insert(WeightEntry(date: date, weightKg: weightKg))
    }
    return ContentView()
        .modelContainer(container)
}

#Preview("記録なし") {
    ContentView()
        .modelContainer(for: WeightEntry.self, inMemory: true)
}
