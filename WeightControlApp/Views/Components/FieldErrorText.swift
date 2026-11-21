import SwiftUI

/// 入力欄の下（Form の Section の footer）に出す、入力の間違いのお知らせ。
///
/// 色だけに頼らず、アイコンも付けて「ここを直してね」が分かるようにします（色の見分けがつきにくい人のため）。
/// VoiceOver では「入力エラー」と前置きして読み上げます。
struct FieldErrorText: View {
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .foregroundStyle(.red)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("入力エラー：\(message)"))
    }
}

#Preview {
    Form {
        Section {
            Text(verbatim: "170")
        } footer: {
            FieldErrorText("100〜250 cm の範囲で入力してください。")
        }
    }
}
