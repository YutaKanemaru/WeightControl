import Foundation
import SwiftData

/// 利用者のプロフィール（1 人分）。
///
/// 基礎代謝やカロリー目安の計算（フェーズ 4）に必要な情報を、一度だけ入力して保存しておくための型です。
/// アプリ内では 1 件だけ作り、設定画面から書き換えます。
///
/// 性別・活動量は `enum`（決まった選択肢の型）で扱いますが、データベースには文字列（`rawValue`）で保存します。
/// こうしておくと、将来選択肢を増やしても保存済みのデータを読み込めなくなる心配が少ないためです。
@Model
final class UserProfile {
    /// 身長（cm）
    var heightCm: Double
    /// 生まれた年（西暦）。年齢は毎年変わるので、年齢そのものではなく生まれ年を保存します。
    var birthYear: Int
    /// 性別（`Sex` の rawValue）
    var sexRawValue: String
    /// ふだんの活動量（`ActivityLevel` の rawValue）
    var activityLevelRawValue: String
    /// 最後に更新した日時
    var updatedAt: Date
    /// 1 日の消費カロリーを何から計算するか（Logic の `EnergyExpenditureMode` の rawValue）。
    /// 後から追加した列ですが、既定値（"automatic"）があるので、保存済みのプロフィールは自動で「自動」として読み込まれます。
    var energyModeRawValue: String = "automatic"

    init(
        heightCm: Double,
        birthYear: Int,
        sex: Sex,
        activityLevel: ActivityLevel,
        updatedAt: Date = .now
    ) {
        self.heightCm = heightCm
        self.birthYear = birthYear
        self.sexRawValue = sex.rawValue
        self.activityLevelRawValue = activityLevel.rawValue
        self.updatedAt = updatedAt
    }

    /// 性別。保存されている文字列から変換して返します（読めない値なら `.female`）。
    var sex: Sex {
        get { Sex(rawValue: sexRawValue) ?? .female }
        set { sexRawValue = newValue.rawValue }
    }

    /// 活動量。保存されている文字列から変換して返します（読めない値なら `.sedentary`）。
    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRawValue) ?? .sedentary }
        set { activityLevelRawValue = newValue.rawValue }
    }
}

extension UserProfile {
    /// 性別。基礎代謝の計算式（Mifflin-St Jeor 式）が男女で係数を変えるために使います。
    nonisolated enum Sex: String, CaseIterable, Identifiable, Sendable {
        case male
        case female

        var id: String { rawValue }
    }

    /// ふだんの活動量。1 日の消費カロリーの目安を出すときに使います（係数は Logic 側で決めます）。
    nonisolated enum ActivityLevel: String, CaseIterable, Identifiable, Sendable {
        /// ほとんど運動しない（デスクワーク中心）
        case sedentary
        /// 週 1〜3 回の軽い運動
        case light
        /// 週 3〜5 回の運動
        case moderate
        /// ほぼ毎日の運動
        case active
        /// 激しい運動・体を使う仕事
        case veryActive

        var id: String { rawValue }
    }
}
