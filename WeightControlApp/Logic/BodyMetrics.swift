import Foundation

/// 体の大きさに関する計算（BMI）。
///
/// BMI（ビーエムアイ）＝ 体重kg ÷ (身長m × 身長m)。体重と身長から出す、体格のおおまかな目安です。
/// 区切りの値は日本肥満学会の基準に合わせています（詳しくは docs/BMI_GOAL.md）。
nonisolated enum BodyMetrics {
    /// BMI の「ふつう」の下限（これ未満は「低め」）
    static let lowerNormalBMI = 18.5
    /// BMI の「ふつう」の上限（この値ちょうど以上は「高め」）
    static let upperNormalBMI = 25.0
    /// 標準体重の BMI（いちばん病気になりにくいとされる値）
    static let standardBMI = 22.0
    /// 小数の誤差で 0.1 kg 単位の丸めがずれないための小さな値
    private static let epsilon = 1e-9

    /// BMI ＝ 体重kg ÷ (身長m × 身長m)。身長が 0 以下なら 0。
    ///
    /// 身長を m に直してから掛けると小数の誤差が出る（1.6 × 1.6 ＝ 2.5600000000000005）ので、
    /// cm のまま「体重 × 10000 ÷ (身長cm × 身長cm)」で計算します。こうすると 160 cm・64 kg がちょうど 25 になります。
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        guard heightCm > 0 else { return 0 }
        return weightKg * 10_000 / (heightCm * heightCm)
    }

    /// その BMI になる体重（kg、丸めなし）
    static func weightKg(forBMI bmi: Double, heightCm: Double) -> Double {
        bmi * heightCm * heightCm / 10_000
    }

    /// BMI が「ふつう」（18.5 以上）になるいちばん軽い体重（kg、0.1 kg 単位で切り上げ）。
    /// 例: 160 cm → 47.36 kg → 47.4 kg
    static func minimumNormalWeightKg(heightCm: Double) -> Double {
        (weightKg(forBMI: lowerNormalBMI, heightCm: heightCm) * 10 - epsilon).rounded(.up) / 10
    }

    /// BMI が「ふつう」（25 未満）に収まるいちばん重い体重（kg、0.1 kg 単位）。
    /// 例: 160 cm → BMI 25 は 64.0 kg ちょうどなので、その 0.1 kg 下の 63.9 kg
    static func maximumNormalWeightKg(heightCm: Double) -> Double {
        let tenths = (weightKg(forBMI: upperNormalBMI, heightCm: heightCm) * 10 - epsilon).rounded(.up) - 1
        return tenths / 10
    }

    /// 標準体重（BMI 22 の体重、kg、0.1 kg 単位で四捨五入）
    static func standardWeightKg(heightCm: Double) -> Double {
        (weightKg(forBMI: standardBMI, heightCm: heightCm) * 10).rounded() / 10
    }

    /// BMI 18.5 を下回るかどうか。
    static func isBelowLowerNormalBMI(weightKg: Double, heightCm: Double) -> Bool {
        bmi(weightKg: weightKg, heightCm: heightCm) < lowerNormalBMI
    }

    /// BMI の区分（画面では「低め・ふつう・高め」と呼びます）
    static func band(forBMI bmi: Double) -> BMIBand {
        if bmi < lowerNormalBMI { return .low }
        if bmi < upperNormalBMI { return .normal }
        return .high
    }
}

/// BMI の区分。日本肥満学会の「低体重・普通体重・肥満」にあたりますが、
/// 責める感じにならないよう、画面では「低め・ふつう・高め」と呼びます。
nonisolated enum BMIBand: Equatable, Sendable {
    /// 18.5 未満
    case low
    /// 18.5 以上 25 未満
    case normal
    /// 25 以上
    case high
}
