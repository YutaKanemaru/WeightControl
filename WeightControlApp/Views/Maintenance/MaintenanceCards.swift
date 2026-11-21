import SwiftUI
import SwiftData

// リバウンド抑制モード（Pro）のホームのカードたち（docs/MAINTENANCE_MODE.md）。
// どれも計算済みの結果（`MaintenanceResult`）を受け取って表示するだけです。

/// kg を小数 1 桁で表示する書式
private let kgFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

// MARK: - モード中：範囲の中にいるか

/// 「達成の見込み」のカードの代わりに出す、リバウンド抑制モードのカード。
/// 状態（範囲の中・そろそろ端・少し上・少し下）、範囲の中の日数、範囲のどのあたりにいるかのバーを出します。
struct MaintenanceStatusCard: View {
    let result: MaintenanceResult
    /// 目標（新しい目標を決める画面を開くため）
    let goal: WeightGoal
    let currentWeightKg: Double?

    var body: some View {
        DashboardCard(title: "リバウンド抑制モード", systemImage: "shield.lefthalf.filled", tint: tint) {
            MetricView(text: Text(headline), caption: caption, tint: tint)

            MaintenanceRangeBar(range: result.range, currentKg: result.currentWeightKg, tint: tint)

            detail

            if result.range.isLowerRaisedForBMI {
                NoticeLabel("下の端は、BMI 18.5 の体重より下げないようにしています。")
            }
            if result.suggestsNewGoal {
                NoticeLabel("新しい目標を決めて、もう一度ゆっくり戻していくこともできます。")
                NavigationLink("新しい目標を決める") {
                    EditGoalView(goal: goal, currentWeightKg: currentWeightKg)
                }
                .font(.callout)
            }
        }
    }

    /// 状態に合わせた色（範囲の中＝緑、それ以外＝オレンジ。赤は使わない）
    private var tint: Color {
        if case .inRange = result.status { return .green }
        return .orange
    }

    private var headline: LocalizedStringKey {
        switch result.status {
        case .inRange: "範囲の中"
        case .nearEdge: "そろそろ端"
        case .above: "範囲より少し上"
        case .below: "範囲より少し下"
        }
    }

    private var caption: Text {
        if result.daysInRange >= MaintenanceAdvisor.maxCountedDays {
            return Text("範囲の中で \(MaintenanceAdvisor.maxCountedDays) 日以上キープ")
        }
        if result.daysInRange > 0 {
            return Text("範囲の中で \(result.daysInRange) 日キープ")
        }
        return Text("キープの範囲 \(result.range.lowerKg, format: kgFormat)〜\(result.range.upperKg, format: kgFormat) kg")
    }

    @ViewBuilder
    private var detail: some View {
        switch result.status {
        case .inRange:
            NoticeLabel("この調子です。いつもの食事と記録を続けましょう。", style: .success)
        case .nearEdge(.up, let days):
            NoticeLabel(text: Text("少しずつ上がっています。このままだと \(days) 日ほどで範囲の上に出そうです。今のうちに整えれば大丈夫です。"), style: .caution)
        case .nearEdge(.down, let days):
            NoticeLabel(text: Text("少しずつ下がっています。このままだと \(days) 日ほどで範囲の下に出そうです。食事をしっかりとりましょう。"), style: .caution)
        case .above(let byKg):
            NoticeLabel(text: Text("範囲より \(byKg, format: kgFormat) kg 上です。あせらず、摂取カロリーの目安を少し控えめにしています。"), style: .caution)
        case .below(let byKg):
            NoticeLabel(text: Text("範囲より \(byKg, format: kgFormat) kg 下です。摂取カロリーの目安を少し多めにしています。"), style: .caution)
        }
    }
}

/// 範囲のどのあたりにいるかを、横長のバーで見せる部品。
/// 範囲の外にいるときも点がはみ出さないよう、バーの左右に少し余白（範囲の幅の半分）をとります。
struct MaintenanceRangeBar: View {
    let range: MaintenanceRange
    let currentKg: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.2))
                    Capsule().fill(Color.green.opacity(0.35))
                        .frame(width: max(0, x(range.upperKg, width) - x(range.lowerKg, width)))
                        .offset(x: x(range.lowerKg, width))
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: x(currentKg, width) - 8)
                }
            }
            .frame(height: 16)

            HStack {
                Text("\(range.lowerKg, format: kgFormat) kg")
                Spacer()
                Text("中心 \(range.centerKg, format: kgFormat) kg")
                Spacer()
                Text("\(range.upperKg, format: kgFormat) kg")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("キープの範囲")
        .accessibilityValue(Text("\(range.lowerKg, format: kgFormat) から \(range.upperKg, format: kgFormat) キログラム。今の目安は \(currentKg, format: kgFormat) キログラム"))
    }

    /// バーの左端〜右端に表示する体重の範囲
    private var displayRange: ClosedRange<Double> {
        let margin = max((range.upperKg - range.lowerKg) / 2, 0.5)
        let low = min(range.lowerKg - margin, currentKg)
        let high = max(range.upperKg + margin, currentKg)
        return low...high
    }

    /// 体重 `kg` をバーの横の位置（pt）に直す
    private func x(_ kg: Double, _ width: CGFloat) -> CGFloat {
        let span = displayRange.upperBound - displayRange.lowerBound
        guard span > 0 else { return width / 2 }
        let ratio = (kg - displayRange.lowerBound) / span
        return CGFloat(min(max(ratio, 0), 1)) * width
    }
}

// MARK: - 目標に届いたとき

/// 目標に届いたときに出すカード。
/// Pro を使えるなら「リバウンド抑制モードを始める」ボタン、使えないなら Pro の案内を出します。
struct GoalAchievedCard: View {
    let goal: WeightGoal
    /// Pro を使えるか
    let isProUnlocked: Bool

    var body: some View {
        DashboardCard(title: "目標達成、おめでとうございます！", systemImage: "trophy.fill", tint: .green) {
            Text("ここからは、届いた体重をキープする時期です。減量のあとは体重が戻りやすいので、範囲を決めて早めに気づけるようにしておくと安心です。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if isProUnlocked {
                Button {
                    goal.startMaintenance()
                } label: {
                    Label("リバウンド抑制モードを始める", systemImage: "shield.lefthalf.filled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Text("\(goal.targetWeightKg, format: kgFormat) kg を中心に ±\(MaintenanceAdvisor.defaultHalfWidthKg, format: kgFormat) kg の範囲でキープします。幅は設定で変えられます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                NoticeLabel("Pro にアップグレードすると「リバウンド抑制モード」が使えます。範囲から出そうなときにやさしく知らせ、キープ用のカロリーの目安を出します。")
                NavigationLink {
                    ProLockedView()
                } label: {
                    Label("Pro について見る", systemImage: "star.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - プレビュー

#Preview("範囲の中") {
    let range = MaintenanceAdvisor.range(centerKg: 62, halfWidthKg: 1.5, heightCm: 165)
    NavigationStack {
        ScrollView {
            MaintenanceStatusCard(
                result: MaintenanceResult(range: range, currentWeightKg: 62.4, status: .inRange,
                                          daysInRange: 30, daysAboveRange: 0, plannedWeeklyChangeKg: 0),
                goal: WeightGoal(targetWeightKg: 62, deadline: .now),
                currentWeightKg: 62.4
            )
            .padding()
        }
    }
    .modelContainer(.preview())
}

#Preview("範囲より上・大きい文字") {
    let range = MaintenanceAdvisor.range(centerKg: 62, halfWidthKg: 1.5, heightCm: 165)
    NavigationStack {
        ScrollView {
            MaintenanceStatusCard(
                result: MaintenanceResult(range: range, currentWeightKg: 64.1, status: .above(byKg: 0.6),
                                          daysInRange: 0, daysAboveRange: 30, plannedWeeklyChangeKg: -0.16),
                goal: WeightGoal(targetWeightKg: 62, deadline: .now),
                currentWeightKg: 64.1
            )
            .padding()
        }
    }
    .modelContainer(.preview())
    .dynamicTypeSize(.accessibility2)
}

#Preview("目標達成・無料版") {
    NavigationStack {
        ScrollView {
            GoalAchievedCard(goal: WeightGoal(targetWeightKg: 62, deadline: .now), isProUnlocked: false)
                .padding()
        }
    }
    .modelContainer(.preview())
}
