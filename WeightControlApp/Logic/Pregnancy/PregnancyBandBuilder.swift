import Foundation

/// ある日の「増え方の目安の帯」（妊娠前からの増え方、kg）
nonisolated struct PregnancyBandValue: Equatable, Sendable {
    /// 帯の下の端（妊娠前から +○ kg）
    var lowerGainKg: Double
    /// 帯の上の端（妊娠前から +○ kg）
    var upperGainKg: Double
}

/// グラフに描く帯の 1 点（体重そのもの、kg）
nonisolated struct PregnancyBandPoint: Equatable, Sendable {
    var date: Date
    /// 帯の下の端の体重（kg）
    var lowerKg: Double
    /// 帯の上の端の体重（kg）
    var upperKg: Double
}

/// 週ごとの「増え方の目安の帯」を作る（docs/PREGNANCY_MODE.md の「増え方の目安の帯」）。
///
/// 日本の目安は出産までの合計しか決めていないので、週ごとの帯は **アプリの決まり** です（IOM 2009 の考え方を参考にした）。
/// - 妊娠初期（0〜13 週）：下の端は +0 kg のまま、上の端は 13 週で +2 kg までまっすぐ増やす（つわりで減る人も多いため）。
/// - 13 週〜40 週：13 週の点から、40 週で合計の下の値・上の値に届くようにまっすぐ伸ばす。
/// - 40 週より後は、合計の値のまま。
///
/// SwiftUI / SwiftData には依存しない、ただの計算です。
nonisolated enum PregnancyBandBuilder {
    /// 初期の終わり（13 週 0 日、91 日目）
    static let earlyEndDay = 13 * 7
    /// 初期の終わりまでの上の端（kg）
    static let earlyUpperGainKg = 2.0
    /// グラフの点の間隔（日）
    static let chartStepDays = 7

    /// 妊娠 `day` 日目（0 週 0 日が 0）の帯
    static func band(atDay day: Int, range: PregnancyGainRange) -> PregnancyBandValue {
        let dueDay = GestationalAgeCalculator.dueDay
        let clampedDay = Double(min(max(day, 0), dueDay))
        let earlyEnd = Double(earlyEndDay)
        // 合計の上の値が 2 kg より小さいときは、初期の上の端もそこまで
        let earlyUpper = min(earlyUpperGainKg, range.highKg)
        if clampedDay <= earlyEnd {
            return PregnancyBandValue(lowerGainKg: 0, upperGainKg: earlyUpper * clampedDay / earlyEnd)
        }
        let ratio = (clampedDay - earlyEnd) / (Double(dueDay) - earlyEnd)
        return PregnancyBandValue(
            lowerGainKg: range.lowKg * ratio,
            upperGainKg: earlyUpper + (range.highKg - earlyUpper) * ratio
        )
    }

    /// グラフ用の帯の点（0 週から 40 週まで 1 週ごと、41 点）。体重そのもの（妊娠前の体重 ＋ 増え方）で返す。
    static func chartPoints(
        dueDate: Date,
        prePregnancyWeightKg: Double,
        range: PregnancyGainRange,
        calendar: Calendar = .current
    ) -> [PregnancyBandPoint] {
        let start = GestationalAgeCalculator.startDate(dueDate: dueDate, calendar: calendar)
        return stride(from: 0, through: GestationalAgeCalculator.dueDay, by: chartStepDays).map { day in
            let value = band(atDay: day, range: range)
            return PregnancyBandPoint(
                date: DayMath.date(byAddingDays: day, to: start, calendar: calendar),
                lowerKg: prePregnancyWeightKg + value.lowerGainKg,
                upperKg: prePregnancyWeightKg + value.upperGainKg
            )
        }
    }
}
