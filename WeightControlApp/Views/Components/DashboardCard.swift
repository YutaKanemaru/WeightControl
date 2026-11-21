import SwiftUI

/// 角丸の「カード」の入れ物。ホームだけでなく、ほかの画面でも使い回す共通部品です。
///
/// 上に小さな見出し（SF Symbols のアイコン＋タイトル）、その下に中身を置きます。
/// 背景は `.background.secondary`（システムの色）なので、ダークモードでは自動で暗い色になります。
///
/// 使いかた:
/// ```swift
/// DashboardCard(title: "達成の見込み", systemImage: "flag.checkered") {
///     MetricView("目標まで", value: 2.5, unit: "kg")
/// }
/// ```
struct DashboardCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// 見出しの色。意味のある色（注意＝オレンジなど）だけを渡し、ふだんはアクセントカラー。
    var tint: Color = .accentColor
    /// 見出しの右に出す小さな札（例: "Pro"）。なければ出さない。
    var badge: LocalizedStringKey? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    // VoiceOver で「見出し」として読み上げ、カードの間を移動しやすくする
                    .accessibilityAddTraits(.isHeader)
                if let badge {
                    BadgeLabel(badge)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}

#Preview("カード") {
    ScrollView {
        VStack(spacing: 16) {
            DashboardCard(title: "体重", systemImage: "scalemass") {
                MetricView("最新の体重", value: 64.2, unit: "kg", size: .hero)
            }
            DashboardCard(title: "見込みの幅", systemImage: "arrow.left.and.right", badge: "Pro") {
                Text("札（バッジ）つきの見出しです。")
            }
            DashboardCard(title: "注意の見出し", systemImage: "exclamationmark.triangle", tint: .orange) {
                Text("意味のある色だけを見出しに使います。")
            }
        }
        .padding()
    }
}
