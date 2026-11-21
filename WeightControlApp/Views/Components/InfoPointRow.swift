import SwiftUI

/// 「アイコン＋太めの見出し＋説明文」の 1 行。機能の紹介や、ご利用の前の注意を箇条書きで見せるときに使う共通部品です。
///
/// - アイコンは SF Symbols。色はアクセントカラー（意味のある色を渡すときだけ `tint` を変える）。
/// - アイコンの幅を `@ScaledMetric` で文字サイズに合わせて伸ばすので、大きい文字でも見出しの位置がそろいます。
/// - VoiceOver では見出しと説明をまとめて 1 つとして読み上げます（アイコンは飾りなので読み上げない）。
struct InfoPointRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String
    var tint: Color = .accentColor

    /// アイコンを置く幅（pt）。文字サイズの設定に合わせて大きくなる。
    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 20) {
        InfoPointRow(title: "記録はかんたん", detail: "体重を入れるだけ。グラフで変化が見えます。", systemImage: "scalemass")
        InfoPointRow(title: "データはこの iPhone の中だけ", detail: "外部のサーバーには送りません。", systemImage: "lock.iphone")
    }
    .padding()
}

#Preview("大きい文字・ダークモード") {
    VStack(spacing: 20) {
        InfoPointRow(title: "記録はかんたん", detail: "体重を入れるだけ。グラフで変化が見えます。", systemImage: "scalemass")
    }
    .padding()
    .dynamicTypeSize(.accessibility3)
    .preferredColorScheme(.dark)
}
