import Foundation
import Observation

/// Pro の設定を保存するときのキー（`UserDefaults` で使う名前）。
enum ProPreferenceKey {
    /// 開発用の「Pro を試す」スイッチ（Debug ビルドだけで使う）
    static let debugTrialEnabled = "pro.debugTrialEnabled"
}

/// Pro 機能を使えるかどうかを、アプリ全体に知らせる係。
///
/// アプリで 1 つだけ作り、environment（画面の「共有の持ち物」）で各画面に渡します。
/// `@Observable` なので、スイッチを切りかえると、ホームなどの画面が自動で描き直されます。
///
/// ## 今と、課金を入れたあと
/// - 今：購入のしくみはまだないので `isPurchased` はいつも `false`。
///   Debug ビルドだけ、設定タブの「Pro を試す」スイッチで使えるようにしています。
/// - フェーズ 11（StoreKit）：`isPurchased` を、App Store での購入状況から入れるようにします。
///   画面は `isUnlocked` だけを見ているので、画面側は変えなくて済みます。
///
/// 判断のルールそのものは `Logic/Pro/ProAccessPolicy` にあり、テストで確かめています。
@Observable
final class ProAccess {
    /// Pro を購入済みか（フェーズ 11 で StoreKit の結果を入れる）
    private(set) var isPurchased = false
    /// 開発用の「Pro を試す」スイッチがオンか（Release ビルドでは、オンでも使えません）
    private(set) var isDebugTrialOn: Bool

    @ObservationIgnored private let defaults: UserDefaults

    /// 開発用のスイッチを使ってよいビルドか。`#if DEBUG` なので、App Store に出す Release ビルドでは `false` になります。
    static var allowsDebugTrial: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Pro 機能を使えるか。画面はこれだけを見ます。
    var isUnlocked: Bool {
        ProAccessPolicy.isUnlocked(
            isPurchased: isPurchased,
            isDebugTrialOn: isDebugTrialOn,
            allowsDebugTrial: Self.allowsDebugTrial
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isDebugTrialOn = defaults.bool(forKey: ProPreferenceKey.debugTrialEnabled)
    }

    /// 開発用の「Pro を試す」スイッチを切りかえて、次に開いたときのために保存します。
    func setDebugTrial(_ isOn: Bool) {
        isDebugTrialOn = isOn
        defaults.set(isOn, forKey: ProPreferenceKey.debugTrialEnabled)
    }

    #if DEBUG
    /// プレビュー用：最初から Pro を使える状態（保存はしない）
    static func previewUnlocked() -> ProAccess {
        let access = ProAccess(defaults: UserDefaults(suiteName: "preview.pro") ?? .standard)
        access.isDebugTrialOn = true
        return access
    }
    #endif
}
