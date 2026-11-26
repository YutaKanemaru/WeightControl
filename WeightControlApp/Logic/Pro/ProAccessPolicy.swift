import Foundation

/// Pro の「いまの状態」。画面は、これを見て中身を出すか、ぼかして「Pro で見られます」にするかを決めます。
/// 仕様は docs/PRO.md。
nonisolated enum ProAccessStatus: Equatable, Sendable {
    /// Pro を購入済み
    case purchased
    /// 1 か月の無料お試し中。`endsAt` の 0 時に終わる。`daysLeft` は今日をふくめた残りの日数（1 以上）
    case trial(endsAt: Date, daysLeft: Int)
    /// お試しが終わった（まだ購入していない）
    case trialEnded(endedAt: Date)
    /// まだお試しを始めていない（「1 か月無料で試す」を出せる）
    case trialAvailable
    /// 開発用の「Pro を試す」スイッチで使える状態（Debug ビルドだけ）
    case debugUnlocked

    /// Pro の中身を見せてよいか
    var isUnlocked: Bool {
        switch self {
        case .purchased, .trial, .debugUnlocked: true
        case .trialEnded, .trialAvailable: false
        }
    }
}

/// Pro 機能を使えるかどうかを決めるルール（Pro 機能・フェーズ 12、お試しは docs/PRO.md）。
///
/// ## なぜ分けているのか
/// 「使えるかどうか」の判断をここ 1 か所にまとめておくと、課金（フェーズ 11・StoreKit）を入れるときは
/// `isPurchased`（購入済みか）と `trialStartDate`（お試しを始めた日）を StoreKit の結果に差しかえるだけで済みます。
///
/// ## 1 か月の無料お試し
/// ユーザーが「1 か月無料で試す」を押した日から、次の月の同じ日の 0 時まで Pro を使えます
/// （11 月 21 日に始めたら 12 月 20 日まで）。App Store の決まり（審査ガイドライン 3.1.1）では、
/// 買い切りのアプリの期間限定お試しは「0 円の購入項目」として始めるので、フェーズ 11 では
/// その購入の日付を `trialStartDate` に入れます。購入の記録は Apple 側に残るので、入れ直しても期間は続きます。
///
/// ## 守ること
/// Release ビルド（App Store に出すもの）では `allowsDebugTrial` が `false` になるので、
/// 開発用スイッチの値が何であっても、購入かお試しでなければ Pro は使えません。
nonisolated enum ProAccessPolicy {
    /// お試しの長さ（月）
    static let trialLengthMonths = 1

    /// お試しが終わる日時（始めた日の 0 時から 1 か月後の 0 時）
    static func trialEndDate(startedAt start: Date, calendar: Calendar) -> Date {
        let startDay = calendar.startOfDay(for: start)
        return calendar.date(byAdding: .month, value: trialLengthMonths, to: startDay) ?? startDay
    }

    /// いまの Pro の状態。
    /// - Parameters:
    ///   - isPurchased: Pro を購入済みか（フェーズ 11 で StoreKit の結果を入れる）
    ///   - trialStartDate: お試しを始めた日時（始めていなければ nil）
    ///   - isDebugTrialOn: 開発用の「Pro を試す」スイッチがオンか
    ///   - allowsDebugTrial: 開発用のスイッチを使ってよいビルドか（Debug ビルドだけ `true`）
    static func status(
        isPurchased: Bool,
        trialStartDate: Date?,
        isDebugTrialOn: Bool,
        allowsDebugTrial: Bool,
        now: Date,
        calendar: Calendar
    ) -> ProAccessStatus {
        if isPurchased { return .purchased }
        if allowsDebugTrial && isDebugTrialOn { return .debugUnlocked }
        guard let trialStartDate else { return .trialAvailable }

        let endsAt = trialEndDate(startedAt: trialStartDate, calendar: calendar)
        guard now < endsAt else { return .trialEnded(endedAt: endsAt) }
        let daysLeft = max(DayMath.days(from: now, to: endsAt, calendar: calendar), 1)
        return .trial(endsAt: endsAt, daysLeft: daysLeft)
    }
}
