import Foundation

// このフォルダ（Shared/）のファイルは、アプリ本体とウィジェット（拡張）の両方に入ります。
// ウィジェットには Logic/ や Models/ が入っていないので、ここでは Foundation だけを使います。
// 仕様は docs/WIDGET.md。

/// ウィジェットに出す数字を、アプリがまとめて書き出した「その時点の写し」（スナップショット）。
///
/// アプリは記録や目標が変わるたびにこれを作って App Group（アプリと拡張の共有の保存場所）に保存し、
/// ウィジェットはそれを読んで表示するだけにします。体重の計算はアプリ側（`HomeDashboardBuilder`）の 1 か所だけで行うので、
/// ホームとウィジェットで数字がずれません。
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// 保存する形の版。形を変えたら上げる（古い形のデータは読めなければ捨てて、アプリが作り直すのを待つ）
    static let currentVersion = 1

    var version: Int = WidgetSnapshot.currentVersion
    /// 作った日時
    var generatedAt: Date
    /// 最新の記録の体重（kg）。記録がなければ nil。
    var latestWeightKg: Double?
    /// 最新の記録の日時。記録がなければ nil。
    var latestDate: Date?
    /// 直近 14 日の記録（1 日 1 件、その日の最後の記録。古い順）
    var recentRecords: [WidgetWeightRecord]
    /// 連続記録日数（作った時点の値）。表示するときは `WidgetDisplay.visibleStreakDays` で途切れていないか確かめる
    var streakDays: Int
    /// 目標。目標がなければ nil。キープモード中も入る（そのときは `maintenance` を優先して表示する）
    var goal: WidgetGoalSummary?
    /// キープモード（Pro）の範囲。モード中でなければ nil。
    var maintenance: WidgetMaintenanceSummary?

    /// 記録も目標もない状態（アプリをまだ開いていないときなど）
    static func empty(generatedAt: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: generatedAt, latestWeightKg: nil, latestDate: nil, recentRecords: [], streakDays: 0, goal: nil, maintenance: nil)
    }
}

/// ウィジェットのグラフに出す 1 日分の記録
nonisolated struct WidgetWeightRecord: Codable, Equatable, Sendable {
    var date: Date
    var weightKg: Double
}

/// ウィジェットに出す目標のまとめ
nonisolated struct WidgetGoalSummary: Codable, Equatable, Sendable {
    /// 目標体重（kg）
    var targetWeightKg: Double
    /// 期限
    var deadline: Date
    /// 目標までの残り（kg、いつもプラス）。ホームの「目標まで」と同じ値。計算できなければ nil。
    var remainingKg: Double?
    /// 進み具合（0 = スタート、1 = 達成）。キープが目標のときなどは nil。
    var progress: Double?
    /// 目標に届いた（か通りこした）か
    var isAchieved: Bool
}

/// ウィジェットに出すキープモード（Pro）の範囲
nonisolated struct WidgetMaintenanceSummary: Codable, Equatable, Sendable {
    /// 範囲の下の端（kg）
    var lowerKg: Double
    /// 範囲の上の端（kg）
    var upperKg: Double
    /// 今の体重の目安が範囲の中か
    var isInRange: Bool
}
