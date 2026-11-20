import SwiftUI

/// アイコンつきの短いお知らせ（補足・注意・よい知らせ）。カードの中の小さな一文に使います。
///
/// 色は意味のあるものだけ：補足＝グレー、注意＝オレンジ、よい知らせ＝緑。
/// 責める言い方にならないよう、文面は「〜です」「〜しましょう」のやさしい形にします。
struct NoticeLabel: View {
    enum Style {
        /// 補足（例：計算のしかた）
        case info
        /// 注意（例：予測の精度が低め）
        case caution
        /// よい知らせ（例：期限に間に合うペース）
        case success

        var systemImage: String {
            switch self {
            case .info: "info.circle"
            case .caution: "exclamationmark.triangle.fill"
            case .success: "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: .secondary
            case .caution: .orange
            case .success: .green
            }
        }
    }

    private let text: Text
    private let style: Style

    init(_ key: LocalizedStringKey, style: Style = .info) {
        self.init(text: Text(key), style: style)
    }

    init(text: Text, style: Style = .info) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Label {
            text
                .foregroundStyle(style == .info ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: style.systemImage)
                .foregroundStyle(style.color)
        }
        .font(.footnote)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        NoticeLabel("基礎代謝と活動量から計算しています。")
        NoticeLabel("記録が 7 日分たまるまでは、予測の精度が低めです。", style: .caution)
        NoticeLabel("期限に間に合うペースです", style: .success)
    }
    .padding()
}
