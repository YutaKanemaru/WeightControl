import Foundation
import Observation

/// Pro の設定を保存するときのキー（`UserDefaults` で使う名前）。
enum ProPreferenceKey {
    /// 開発用の「Pro を試す」スイッチ（Debug ビルドだけで使う）
    static let debugTrialEnabled = "pro.debugTrialEnabled"
    /// 1 か月の無料お試しを始めた日時（1970 年からの秒数）。フェーズ 11 では StoreKit の購入日に置きかえる
    static let trialStartDate = "pro.trialStartDate"
    /// ホームの「1 か月無料で試せます」のカードを「あとで」で閉じたか
    static let trialOfferDismissed = "pro.trialOfferDismissed"
}

/// Pro 機能を使えるかどうかを、アプリ全体に知らせる係。仕様は docs/PRO.md。
///
/// アプリで 1 つだけ作り、environment（画面の「共有の持ち物」）で各画面に渡します。
/// `@Observable` なので、お試しを始めたりスイッチを切りかえたりすると、ホームなどの画面が自動で描き直されます。
///
/// ## 今と、課金を入れたあと
/// - 今：購入のしくみはまだないので `isPurchased` はいつも `false`。
///   「1 か月無料で試す」を押した日を、この iPhone の中（`UserDefaults`）に保存しています。
///   アプリを消して入れ直すと、この日付も消えます。
/// - フェーズ 11（StoreKit）：`isPurchased` を App Store での購入状況から、
///   お試しを始めた日を「0 円のお試し」の購入日から入れるようにします（Apple 側に残るので入れ直しても消えない）。
///   画面は `status` と `isUnlocked` だけを見ているので、画面側は変えなくて済みます。
///
/// 判断のルールそのものは `Logic/Pro/ProAccessPolicy` にあり、テストで確かめています。
@Observable
final class ProAccess {
    /// Pro を購入済みか（フェーズ 11 で StoreKit の結果を入れる）
    private(set) var isPurchased = false
    /// お試しを始めた日時（始めていなければ nil）
    private(set) var trialStartDate: Date?
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

    /// いまの Pro の状態（購入済み・お試し中・お試し終了・まだ始めていない）
    func status(now: Date = .now, calendar: Calendar = .current) -> ProAccessStatus {
        ProAccessPolicy.status(
            isPurchased: isPurchased,
            trialStartDate: trialStartDate,
            isDebugTrialOn: isDebugTrialOn,
            allowsDebugTrial: Self.allowsDebugTrial,
            now: now,
            calendar: calendar
        )
    }

    /// Pro 機能を使えるか。画面はこれ（か `status`）だけを見ます。
    var isUnlocked: Bool { status().isUnlocked }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isDebugTrialOn = defaults.bool(forKey: ProPreferenceKey.debugTrialEnabled)
        if let seconds = defaults.object(forKey: ProPreferenceKey.trialStartDate) as? Double {
            self.trialStartDate = Date(timeIntervalSince1970: seconds)
        }
    }

    /// 「1 か月無料で試す」：お試しを始める。すでに始めていれば何もしない（やり直しはできない）。
    ///
    /// フェーズ 11 では、ここで 0 円のお試しの購入（StoreKit）を行います。
    func startTrial(now: Date = .now) {
        guard trialStartDate == nil else { return }
        saveTrialStartDate(now)
    }

    /// 開発用の「Pro を試す」スイッチを切りかえて、次に開いたときのために保存します。
    func setDebugTrial(_ isOn: Bool) {
        isDebugTrialOn = isOn
        defaults.set(isOn, forKey: ProPreferenceKey.debugTrialEnabled)
    }

    private func saveTrialStartDate(_ date: Date?) {
        trialStartDate = date
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: ProPreferenceKey.trialStartDate)
        } else {
            defaults.removeObject(forKey: ProPreferenceKey.trialStartDate)
        }
    }

    #if DEBUG
    /// 開発用：お試しを始めた日を自由に変える（nil で「まだ始めていない」に戻す）。
    /// お試し中・お試し終了の画面を確かめるためのもので、Release ビルドには入りません。
    func debugSetTrialStartDate(_ date: Date?) {
        saveTrialStartDate(date)
    }

    /// プレビュー用：最初から Pro を使える状態（保存はしない）
    static func previewUnlocked() -> ProAccess {
        let access = ProAccess(defaults: UserDefaults(suiteName: "preview.pro.unlocked") ?? .standard)
        access.isDebugTrialOn = true
        return access
    }

    /// プレビュー用：お試しが終わった状態（中身がぼかして表示される）
    static func previewTrialEnded() -> ProAccess {
        let access = ProAccess(defaults: UserDefaults(suiteName: "preview.pro.ended") ?? .standard)
        access.isDebugTrialOn = false
        access.trialStartDate = Calendar.current.date(byAdding: .month, value: -2, to: .now)
        return access
    }
    #endif
}
