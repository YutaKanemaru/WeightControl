import SwiftUI

/// Pro を使えないときに、Pro の画面の代わりに出す案内。
///
/// 課金のしくみ（フェーズ 11）ができるまでは「準備中」とだけ伝えます。
/// 購入ボタンは、StoreKit を入れるときにここへ追加します。
struct ProLockedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Pro の機能です", systemImage: "lock")
        } description: {
            Text("チートデーの提案と見込みの幅は、Pro で使える機能です。アプリの中で購入できるよう準備しています。")
        }
    }
}

#Preview {
    ProLockedView()
}
