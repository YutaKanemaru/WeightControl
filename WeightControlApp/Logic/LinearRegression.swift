import Foundation

/// 直線 `y = slope × x + intercept`。
nonisolated struct LinearFit: Equatable, Sendable {
    /// 傾き（x が 1 増えたときに y がどれだけ増えるか）
    var slope: Double
    /// 切片（x = 0 のときの y）
    var intercept: Double

    func value(at x: Double) -> Double {
        slope * x + intercept
    }
}

/// 線形回帰（最小二乗法）：点の集まりに、いちばん当てはまりのよい直線を引く計算。
///
/// 「各点と直線との縦のずれ」を 2 乗して合計した値が最も小さくなる直線を求めます。
/// このアプリでは、x = 日数、y = トレンド体重 として、傾き（1 日に何 kg 変わっているか）を知るために使います。
nonisolated enum LinearRegression {
    /// 点が 2 つ未満、または x がすべて同じ（縦一直線で傾きが決まらない）ときは `nil` を返します。
    static func fit(_ samples: [(x: Double, y: Double)]) -> LinearFit? {
        guard samples.count >= 2 else { return nil }

        let count = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / count
        let meanY = samples.reduce(0) { $0 + $1.y } / count

        var sumXY = 0.0  // x と y のずれの掛け算の合計（共分散のもと）
        var sumXX = 0.0  // x のずれの 2 乗の合計（分散のもと）
        for sample in samples {
            let dx = sample.x - meanX
            sumXY += dx * (sample.y - meanY)
            sumXX += dx * dx
        }
        guard sumXX > 0 else { return nil }

        let slope = sumXY / sumXX
        return LinearFit(slope: slope, intercept: meanY - slope * meanX)
    }
}

nonisolated extension LinearRegression {
    /// 傾きの「標準誤差」：点が直線のまわりにどれくらいばらついているかから見た、傾きの不確かさ。
    ///
    ///     標準誤差 ＝ √( 残差の 2 乗の合計 ÷ (点の数 − 2) ÷ x のずれの 2 乗の合計 )
    ///
    /// - 残差：各点と直線との縦のずれ
    /// - 点が直線にぴったり乗っていれば 0、ばらつくほど大きくなります。
    /// - 点が多く、x（日数）が広くばらけているほど小さくなります（＝傾きを信じやすい）。
    ///
    /// 点が 3 つ未満、または x がすべて同じなら `nil`。
    static func slopeStandardError(_ samples: [(x: Double, y: Double)], fit: LinearFit) -> Double? {
        guard samples.count >= 3 else { return nil }

        let count = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / count
        var sumSquaredResiduals = 0.0
        var sumXX = 0.0
        for sample in samples {
            let residual = sample.y - fit.value(at: sample.x)
            sumSquaredResiduals += residual * residual
            let dx = sample.x - meanX
            sumXX += dx * dx
        }
        guard sumXX > 0 else { return nil }

        let residualVariance = sumSquaredResiduals / (count - 2)
        return (residualVariance / sumXX).squareRoot()
    }
}
