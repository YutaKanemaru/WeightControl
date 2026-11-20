import SwiftUI

/// 「大きく太い数字＋単位＋小さい説明」を表示する共通部品。
///
/// いちばん伝えたい数字（体重・目標まで・カロリーなど）を、運動中でもひと目で読めるように大きく出します。
/// - 数字は `monospacedDigit()`（等幅の数字）にして、値が変わっても桁の位置がずれないようにします。
/// - 文字の大きさは Dynamic Type（設定アプリの文字サイズ）に合わせて大きくなります。
///   `.hero` だけは固定の大きさを `@ScaledMetric` で文字サイズに合わせて伸び縮みさせています。
/// - VoiceOver では「タイトル・数字・単位・説明」をまとめて 1 つとして読み上げます。
struct MetricView: View {
    /// 数字の大きさ
    enum Size {
        /// 画面でいちばん大事な数字（ホームの体重など）
        case hero
        /// カードの主役の数字
        case large
        /// 並べて見せる、少し小さめの数字
        case medium
    }

    private let title: LocalizedStringKey?
    private let value: Text
    private let unit: LocalizedStringKey?
    private let caption: Text?
    private let size: Size
    private let tint: Color

    /// `.hero` の数字の大きさ（pt）。文字サイズの設定に合わせて、`largeTitle` と同じ割合で大きくなる。
    @ScaledMetric(relativeTo: .largeTitle) private var heroPointSize: CGFloat = 56

    /// 数値（小数）を表示する。例: `MetricView("最新の体重", value: 64.2, unit: "kg")`
    init(
        _ title: LocalizedStringKey? = nil,
        value: Double,
        fractionLength: Int = 1,
        unit: LocalizedStringKey? = nil,
        caption: Text? = nil,
        size: Size = .large,
        tint: Color = .primary
    ) {
        self.init(
            title,
            text: Text(value, format: .number.precision(.fractionLength(fractionLength))),
            unit: unit,
            caption: caption,
            size: size,
            tint: tint
        )
    }

    /// 数字以外（日付など）も含めて、表示する文字を自分で作って渡す。
    init(
        _ title: LocalizedStringKey? = nil,
        text: Text,
        unit: LocalizedStringKey? = nil,
        caption: Text? = nil,
        size: Size = .large,
        tint: Color = .primary
    ) {
        self.title = title
        self.value = text
        self.unit = unit
        self.caption = caption
        self.size = size
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                value
                    .font(valueFont)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if let unit {
                    Text(unit)
                        .font(unitFont)
                        .fontWeight(.semibold)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
            }
            if let caption {
                caption
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var valueFont: Font {
        switch size {
        case .hero: .system(size: heroPointSize)
        case .large: .largeTitle
        case .medium: .title2
        }
    }

    private var unitFont: Font {
        switch size {
        case .hero: .title2
        case .large: .title3
        case .medium: .body
        }
    }
}

#Preview("数字の大きさ") {
    VStack(alignment: .leading, spacing: 24) {
        MetricView("最新の体重", value: 64.2, unit: "kg", caption: Text("今日 7:30"), size: .hero)
        MetricView("1 日の摂取カロリーの目安", value: 1526, fractionLength: 0, unit: "kcal")
        MetricView("目標まで", value: 2.6, unit: "kg", size: .medium, tint: .green)
    }
    .padding()
}

#Preview("大きい文字（アクセシビリティ）") {
    VStack(alignment: .leading, spacing: 24) {
        MetricView("最新の体重", value: 64.2, unit: "kg", caption: Text("今日 7:30"), size: .hero)
        MetricView("目標まで", value: 2.6, unit: "kg", size: .medium)
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
}
