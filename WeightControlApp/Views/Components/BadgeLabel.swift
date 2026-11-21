import SwiftUI

/// 見出しの横に出す、小さな札（バッジ）。「Pro」の機能であることを示すのに使います。
///
/// 色はアクセントカラーを薄く敷くだけにして、目立ちすぎないようにしています。
struct BadgeLabel: View {
    private let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: .capsule)
    }
}

#Preview {
    VStack(spacing: 12) {
        BadgeLabel("Pro")
        BadgeLabel("Pro")
            .dynamicTypeSize(.accessibility3)
            .preferredColorScheme(.dark)
    }
    .padding()
}
