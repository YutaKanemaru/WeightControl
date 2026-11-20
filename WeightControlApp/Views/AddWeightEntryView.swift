import SwiftUI
import SwiftData

/// 体重を入力して保存する画面（シートで表示）。
///
/// 「すぐ記録できる」ことを優先しています。
/// - 前回の体重を最初から入れておく。毎日の体重は前回と少ししか違わないので、
///   「−」「＋」ボタン（0.1 kg ずつ）で合わせて「記録する」を押すだけで済みます。
/// - キーボードで打つときは、入っている数字が選ばれた状態なので、そのまま打てば置き換わります。
/// - 数字は大きく太く（`monospacedDigit()` で桁がずれない）、運動の後でもひと目で読めるようにしています。
struct AddWeightEntryView: View {
    @Environment(\.modelContext) private var modelContext
    /// この画面を閉じるための関数。環境（Environment）から受け取る。
    @Environment(\.dismiss) private var dismiss
    /// ヘルスケア連携の係（プレビューなどで渡されていないときは nil）
    @Environment(HealthSyncController.self) private var health: HealthSyncController?

    /// 前回の体重。入力欄の初期値に使う。記録がなければ nil。
    let lastWeightKg: Double?
    /// 前回の記録の日時（「前回 64.5 kg・11月19日」の表示用）。わからなければ nil。
    let lastEntryDate: Date?

    @State private var date = Date.now
    @State private var weightText: String
    /// 入力欄で選ばれている範囲。最初は数字全体を選んでおき、打てば置き換わるようにする。
    @State private var selection: TextSelection?
    @State private var errorMessage: String?
    /// 「−」「＋」を押した回数。押したときだけ軽い手ごたえ（触覚フィードバック）を返すための合図。
    @State private var stepCount = 0
    /// キーボードを自動で出すために、入力欄にフォーカス（選択状態）を当てる
    @FocusState private var isWeightFieldFocused: Bool

    /// 大きな数字の大きさ（pt）。文字サイズの設定に合わせて伸び縮みする（`MetricView` の `.hero` と同じ考え方）。
    @ScaledMetric(relativeTo: .largeTitle) private var numberPointSize: CGFloat = 64

    init(lastWeightKg: Double?, lastEntryDate: Date? = nil) {
        self.lastWeightKg = lastWeightKg
        self.lastEntryDate = lastEntryDate
        // `@State` の最初の値は、init の中では `_名前 = State(initialValue:)` の形で入れる
        _weightText = State(initialValue: lastWeightKg.map(WeightEntryStepper.text(for:)) ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weightCard
                    dateCard
                }
                .padding()
            }
            .navigationTitle("体重を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            // 画面のいちばん下（キーボードのすぐ上）に大きな保存ボタンを置く。
            // 数字用のキーボードには「完了」キーがないので、親指で押しやすい位置に置いています。
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("記録する")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .onAppear {
                isWeightFieldFocused = true
                selectAllText()
            }
            // 入力し直し始めたら、エラー表示を消す
            .onChange(of: weightText) { errorMessage = nil }
        }
    }

    // MARK: - カード

    /// 体重の大きな数字と「−」「＋」ボタン
    private var weightCard: some View {
        DashboardCard(title: "体重", systemImage: "scalemass") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("体重", text: $weightText, selection: $selection, prompt: Text(verbatim: "65.0"))
                    .keyboardType(.decimalPad)
                    .focused($isWeightFieldFocused)
                    .font(.system(size: numberPointSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("体重（キログラム）")
                Text("kg")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 12) {
                stepButton(steps: -1, title: "0.1 kg 減らす", systemImage: "minus")
                stepButton(steps: 1, title: "0.1 kg 増やす", systemImage: "plus")
                Spacer(minLength: 0)
            }
            // ボタンを押すたびに、軽い手ごたえ（触覚フィードバック）を返す
            .sensoryFeedback(.selection, trigger: stepCount)

            if let errorMessage {
                NoticeLabel(text: Text(errorMessage), style: .caution)
            } else if let lastWeightKg {
                NoticeLabel(text: previousText(weightKg: lastWeightKg))
            } else {
                NoticeLabel("体重計の数字をそのまま入力してください。")
            }
        }
    }

    /// 測った日時
    private var dateCard: some View {
        DashboardCard(title: "日時", systemImage: "calendar") {
            // 未来の日時は選べないようにする
            DatePicker("測った日時", selection: $date, in: ...Date.now)
        }
    }

    /// 0.1 kg ずつ動かす丸いボタン
    private func stepButton(steps: Int, title: LocalizedStringKey, systemImage: String) -> some View {
        Button {
            if let newText = WeightEntryStepper.adjusted(weightText, steps: steps, fallbackKg: lastWeightKg) {
                weightText = newText
                // 選択を外して、ボタンで動かした数字がそのまま見えるようにする
                selection = nil
                stepCount += 1
            }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    /// 「前回 64.5 kg（11月19日）」の文
    private func previousText(weightKg: Double) -> Text {
        let weight = weightKg.formatted(.number.precision(.fractionLength(1)))
        if let lastEntryDate {
            let day = lastEntryDate.formatted(.dateTime.month().day())
            return Text("前回 \(weight) kg（\(day)）")
        }
        return Text("前回 \(weight) kg")
    }

    /// 入力欄の文字全体を選んだ状態にする
    private func selectAllText() {
        guard !weightText.isEmpty else { return }
        selection = TextSelection(range: weightText.startIndex..<weightText.endIndex)
    }

    // MARK: - 保存

    private func save() {
        // 文字列 → 数値の変換と入力チェックは Logic 側に任せる
        switch WeightInputParser.parse(weightText) {
        case .success(let weightKg):
            // insert するだけで SwiftData が自動で保存してくれる
            let entry = WeightEntry(date: date, weightKg: weightKg)
            modelContext.insert(entry)
            // 設定でオンなら、ヘルスケアにも書き込む（終わるのを待たずに画面を閉じる）
            if let health {
                Task { await health.exportNewEntry(entry) }
            }
            dismiss()
        case .failure(let error):
            errorMessage = message(for: error)
        }
    }

    private func message(for error: WeightInputParser.ParseError) -> String {
        switch error {
        case .empty:
            String(localized: "体重を入力してください。")
        case .notANumber:
            String(localized: "数字で入力してください（例: 65.4）。")
        case .outOfRange:
            String(localized: "20〜300 kg の範囲で入力してください。")
        }
    }
}

#Preview("前回の記録あり") {
    AddWeightEntryView(lastWeightKg: 64.5, lastEntryDate: .now.addingTimeInterval(-86_400))
        .modelContainer(for: WeightEntry.self, inMemory: true)
}

#Preview("はじめての記録") {
    AddWeightEntryView(lastWeightKg: nil)
        .modelContainer(for: WeightEntry.self, inMemory: true)
}

#Preview("ダークモード") {
    AddWeightEntryView(lastWeightKg: 64.5, lastEntryDate: .now.addingTimeInterval(-86_400))
        .modelContainer(for: WeightEntry.self, inMemory: true)
        .preferredColorScheme(.dark)
}

#Preview("大きい文字") {
    AddWeightEntryView(lastWeightKg: 64.5, lastEntryDate: .now.addingTimeInterval(-86_400))
        .modelContainer(for: WeightEntry.self, inMemory: true)
        .dynamicTypeSize(.accessibility3)
}
