import Foundation

/// Pro 機能を使えるかどうかを決めるルール（Pro 機能・フェーズ 12）。
///
/// ## なぜ分けているのか
/// 今はまだ課金のしくみ（フェーズ 11・StoreKit）がないので、開発中に Pro の画面を試せるよう、
/// Debug ビルド（Xcode から実行したとき）だけ「Pro を試す」スイッチで使えるようにしています。
/// 「使えるかどうか」の判断をここ 1 か所にまとめておくと、あとで課金を入れるときは
/// `isPurchased`（購入済みか）を StoreKit の結果に差しかえるだけで済みます。
///
/// ## 守ること
/// Release ビルド（App Store に出すもの）では `allowsDebugTrial` が `false` になるので、
/// スイッチの値が何であっても、購入していなければ Pro は使えません。
nonisolated enum ProAccessPolicy {
    /// - Parameters:
    ///   - isPurchased: Pro を購入済みか（フェーズ 11 で StoreKit の結果を入れる。今はいつも `false`）
    ///   - isDebugTrialOn: 開発用の「Pro を試す」スイッチがオンか
    ///   - allowsDebugTrial: 開発用のスイッチを使ってよいビルドか（Debug ビルドだけ `true`）
    static func isUnlocked(isPurchased: Bool, isDebugTrialOn: Bool, allowsDebugTrial: Bool) -> Bool {
        isPurchased || (allowsDebugTrial && isDebugTrialOn)
    }
}
