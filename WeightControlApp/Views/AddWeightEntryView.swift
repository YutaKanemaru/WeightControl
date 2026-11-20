import SwiftUI
import SwiftData

/// 体重を入力して保存する画面（シートで表示）。
struct AddWeightEntryView: View {
    @Environment(\.modelContext) private var modelContext
    /// この画面を閉じるための関数。環境（Environment）から受け取る。
    @Environment(\.dismiss) private var dismiss
    /// ヘルスケア連携の係（プレビューなどで渡されていないときは nil）
    @Environment(HealthSyncController.self) private var health: HealthSyncController?

    /// 前回の体重（入力欄のうすい見本表示に使う）。記録がなければ nil。
    let lastWeightKg: Double?

    @State private var date = Date.now
    @State private var weightText = ""
    @State private var errorMessage: String?
    /// キーボードを自動で出すために、入力欄にフォーカス（選択状態）を当てる
    @FocusState private var isWeightFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("体重", text: $weightText, prompt: Text(placeholder))
                            .keyboardType(.decimalPad)
                            .focused($isWeightFieldFocused)
                            .font(.title2.monospacedDigit())
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("体重")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    // 未来の日時は選べないようにする
                    DatePicker("日時", selection: $date, in: ...Date.now)
                }
            }
            .navigationTitle("体重を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .onAppear { isWeightFieldFocused = true }
            // 入力し直し始めたら、エラー表示を消す
            .onChange(of: weightText) { errorMessage = nil }
        }
    }

    /// 入力欄のうすい見本。前回の体重があればそれを見せる。
    private var placeholder: String {
        if let lastWeightKg {
            lastWeightKg.formatted(.number.precision(.fractionLength(1)))
        } else {
            "65.0"
        }
    }

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

#Preview {
    AddWeightEntryView(lastWeightKg: 64.5)
        .modelContainer(for: WeightEntry.self, inMemory: true)
}
