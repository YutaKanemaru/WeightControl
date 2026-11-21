import SwiftUI
import SwiftData

/// 設定タブの「目標」の欄に、リバウンド抑制モード中だけ出す行。
///
/// キープの範囲を大きく見せ、範囲の幅（±1.0 / ±1.5 / ±2.0 kg）を選べるようにします。
/// モードを終えるのは「新しい目標を決める」で目標を保存したときだけです（docs/MAINTENANCE_MODE.md）。
struct MaintenanceSettingsRows: View {
    @Bindable var goal: WeightGoal
    let currentWeightKg: Double?
    /// 下の端を BMI 18.5 で止めるのに使う身長。プロフィールがなければ nil。
    let heightCm: Double?

    private let kgFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

    var body: some View {
        let range = MaintenanceAdvisor.range(
            centerKg: goal.targetWeightKg,
            halfWidthKg: goal.maintenanceHalfWidthKg,
            heightCm: heightCm
        )

        VStack(alignment: .leading, spacing: 8) {
            Label("リバウンド抑制モード中", systemImage: "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            MetricView(
                "キープの範囲",
                text: Text("\(range.lowerKg, format: kgFormat)〜\(range.upperKg, format: kgFormat)"),
                unit: "kg",
                caption: Text("中心 \(range.centerKg, format: kgFormat) kg"),
                size: .medium
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)

        Picker(selection: $goal.maintenanceHalfWidthKg) {
            ForEach(MaintenanceAdvisor.halfWidthChoicesKg, id: \.self) { width in
                Text("±\(width, format: kgFormat) kg").tag(width)
            }
        } label: {
            Label("範囲の幅", systemImage: "arrow.left.and.right")
        }

        NavigationLink {
            EditGoalView(goal: goal, currentWeightKg: currentWeightKg)
        } label: {
            Label("新しい目標を決める", systemImage: "flag")
        }
        .accessibilityHint(Text("目標を保存すると、リバウンド抑制モードを終えます"))
    }
}

#Preview {
    let goal = WeightGoal(targetWeightKg: 62, deadline: .now, maintenanceStartDate: .now)
    NavigationStack {
        List {
            Section("目標") {
                MaintenanceSettingsRows(goal: goal, currentWeightKg: 62.3, heightCm: 165)
            }
        }
    }
    .modelContainer(.preview())
}
