import Foundation

// 保存データ（Models/）の型を、計算ロジック（Logic/）の型に変換します。
//
// Logic は SwiftData に依存しないように、自分専用の型（BiologicalSex など）を使っています。
// そのため、画面側でここを通して「保存データ → 計算用の値」に詰め替えてから渡します。

/// 計算ロジック側の活動量（`Logic/CalorieCalculator.swift` の `ActivityLevel`）の別名。
/// `UserProfile.ActivityLevel` の中で単に `ActivityLevel` と書くと、自分自身（保存データ側）を指してしまうため、
/// ファイルの一番外側でこの別名を作っておきます。
typealias CalculatorActivityLevel = ActivityLevel

extension UserProfile.Sex {
    /// カロリー計算で使う性別
    var biologicalSex: BiologicalSex {
        switch self {
        case .male: .male
        case .female: .female
        }
    }
}

extension UserProfile.ActivityLevel {
    /// カロリー計算で使う活動量
    var calculatorLevel: CalculatorActivityLevel {
        switch self {
        case .sedentary: .sedentary
        case .light: .light
        case .moderate: .moderate
        case .active: .active
        case .veryActive: .veryActive
        }
    }
}

extension UserProfile {
    /// 消費カロリーの計算方法。保存されている文字列から変換して返します（読めない値なら `.automatic`）。
    var energyMode: EnergyExpenditureMode {
        get { EnergyExpenditureMode(rawValue: energyModeRawValue) ?? .automatic }
        set { energyModeRawValue = newValue.rawValue }
    }

    /// ホーム画面の計算用の値
    var dashboardProfile: DashboardProfile {
        DashboardProfile(
            heightCm: heightCm,
            birthYear: birthYear,
            sex: sex.biologicalSex,
            activityLevel: activityLevel.calculatorLevel,
            energyMode: energyMode
        )
    }
}

extension WeightGoal {
    /// ホーム画面の計算用の値
    var dashboardGoal: DashboardGoal {
        DashboardGoal(targetWeightKg: targetWeightKg, deadline: deadline, startWeightKg: startWeightKg)
    }
}
