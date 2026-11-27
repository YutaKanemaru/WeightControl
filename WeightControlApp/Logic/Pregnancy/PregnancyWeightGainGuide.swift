import Foundation

/// 妊娠前の体格（妊娠前の BMI で 4 つに分ける）。画面では「低め・ふつう・高め・かなり高め」と呼びます。
nonisolated enum PrePregnancyBodyType: Equatable, Sendable {
    /// BMI 18.5 未満
    case low
    /// BMI 18.5 以上 25.0 未満
    case normal
    /// BMI 25.0 以上 30.0 未満
    case high
    /// BMI 30.0 以上
    case veryHigh

    static func classify(bmi: Double) -> PrePregnancyBodyType {
        switch bmi {
        case ..<18.5: .low
        case ..<25.0: .normal
        case ..<30.0: .high
        default: .veryHigh
        }
    }
}

/// 出産までに増える体重の目安（妊娠前からの合計、kg）。
nonisolated struct PregnancyGainRange: Equatable, Sendable {
    /// 合計の下の値（kg）。「○ kg まで」だけのときは 0。
    var lowKg: Double
    /// 合計の上の値（kg）
    var highKg: Double
}

/// アプリが一般的な目安を出さない理由
nonisolated enum PregnancyNoGuideReason: Equatable, Sendable {
    /// 赤ちゃんが 2 人以上
    case multiple
    /// 妊娠前の BMI が 30 以上（日本の目安は「個別対応・上限 5 kg までが目安」）
    case veryHighBMI
}

/// 帯と判定に使う目安
nonisolated enum PregnancyGainTarget: Equatable, Sendable {
    /// 日本の 2021 年の一般的な目安
    case general(PregnancyGainRange, bodyType: PrePregnancyBodyType)
    /// 健診で医師・助産師から言われた目安（入れたときはこちらを優先）
    case custom(PregnancyGainRange)
    /// アプリからは一般的な目安を出さない（医師の目安を入れてもらう）
    case needsDoctor(PregnancyNoGuideReason)

    /// 帯に使う範囲。目安がないときは nil。
    var range: PregnancyGainRange? {
        switch self {
        case .general(let range, _), .custom(let range): range
        case .needsDoctor: nil
        }
    }
}

/// 医師の目安の入力のまちがい
nonisolated enum PregnancyCustomRangeError: Equatable, Sendable {
    /// 0〜30 kg の範囲の外
    case outOfRange
    /// 下の値が上の値より大きい
    case lowAboveHigh
}

/// 妊娠中の体重増加の目安（docs/PREGNANCY_MODE.md）。
///
/// 数字は日本産科婦人科学会「妊娠中の体重増加の目安」（2021 年 3 月。厚生労働省「妊娠前からはじめる妊産婦のための食生活指針」）：
///
/// | 妊娠前の BMI | 出産までの合計 |
/// |---|---|
/// | 18.5 未満 | 12〜15 kg |
/// | 18.5 以上 25.0 未満 | 10〜13 kg |
/// | 25.0 以上 30.0 未満 | 7〜10 kg |
/// | 30.0 以上 | 個別対応（上限 5 kg までが目安） |
///
/// SwiftUI / SwiftData には依存しない、ただの計算です。
nonisolated enum PregnancyWeightGainGuide {
    /// BMI 30 以上のときに文で伝える上限の目安（kg）
    static let veryHighBMIUpperHintKg = 5.0
    /// 医師の目安として入れられる範囲（kg）
    static let customRangeLimitKg = 0.0...30.0

    /// 体格ごとの一般的な目安（BMI 30 以上は個別対応なので nil）
    static func generalRange(for bodyType: PrePregnancyBodyType) -> PregnancyGainRange? {
        switch bodyType {
        case .low: PregnancyGainRange(lowKg: 12, highKg: 15)
        case .normal: PregnancyGainRange(lowKg: 10, highKg: 13)
        case .high: PregnancyGainRange(lowKg: 7, highKg: 10)
        case .veryHigh: nil
        }
    }

    /// 帯と判定に使う目安を決める。
    ///
    /// - 医師の目安（`customHighKg`）があれば、いつもそれを使う（下の値がなければ 0 kg から）。
    /// - なければ、赤ちゃんが 2 人以上・BMI 30 以上のときは「医師の目安を入れてください」、それ以外は一般的な目安。
    /// - Parameters:
    ///   - prePregnancyWeightKg: 妊娠前の体重（kg）
    ///   - heightCm: 身長（cm）
    static func target(
        prePregnancyWeightKg: Double,
        heightCm: Double,
        isMultiple: Bool,
        customLowKg: Double?,
        customHighKg: Double?
    ) -> PregnancyGainTarget {
        if let customHighKg, validateCustomRange(lowKg: customLowKg, highKg: customHighKg) == nil {
            return .custom(PregnancyGainRange(lowKg: customLowKg ?? 0, highKg: customHighKg))
        }
        if isMultiple {
            return .needsDoctor(.multiple)
        }
        let bodyType = bodyType(prePregnancyWeightKg: prePregnancyWeightKg, heightCm: heightCm)
        guard let range = generalRange(for: bodyType) else {
            return .needsDoctor(.veryHighBMI)
        }
        return .general(range, bodyType: bodyType)
    }

    /// 妊娠前の体格
    static func bodyType(prePregnancyWeightKg: Double, heightCm: Double) -> PrePregnancyBodyType {
        PrePregnancyBodyType.classify(bmi: BodyMetrics.bmi(weightKg: prePregnancyWeightKg, heightCm: heightCm))
    }

    /// 医師の目安の入力のチェック。正しければ nil。
    static func validateCustomRange(lowKg: Double?, highKg: Double) -> PregnancyCustomRangeError? {
        let values = [lowKg, highKg].compactMap { $0 }
        if values.contains(where: { !customRangeLimitKg.contains($0) }) {
            return .outOfRange
        }
        if let lowKg, lowKg > highKg {
            return .lowAboveHigh
        }
        return nil
    }
}

/// 医師の目安の入力欄の読み取り結果
nonisolated enum PregnancyGainTextResult: Equatable, Sendable {
    /// 空欄（入れていない）
    case empty
    /// 読み取れた値（kg、0.1 kg 単位に丸めた値）
    case value(Double)
    /// 数字として読めない
    case invalid
}

nonisolated extension PregnancyWeightGainGuide {
    /// 医師の目安の入力欄（「10」「10.5」「１０，５」など）を kg に読み取る。範囲のチェックは `validateCustomRange` で行う。
    static func parseGainText(_ text: String) -> PregnancyGainTextResult {
        let halfwidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let normalized = halfwidth
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return .empty }
        guard let value = Double(normalized), value.isFinite else { return .invalid }
        return .value((value * 10).rounded() / 10)
    }
}

/// 妊娠中モードが、ほかの機能（目標・予測・カロリーなど）にどう効いているか
nonisolated enum PregnancyModeState: Equatable, Sendable {
    /// 妊娠中モードではない（ふだんどおり）
    case off
    /// 妊娠中モード中：減量のための機能をすべて止め、目標は使わない
    case active
    /// モードを終えたあと、前の目標を一時停止している（新しい目標を決めるか、「前の目標に戻す」を押すまで）
    case goalPausedAfterPregnancy

    /// 目標（とそれにつながる予測・カロリーなど）を使うか
    var usesGoal: Bool { self == .off }
}

nonisolated extension PregnancyWeightGainGuide {
    /// 妊娠中モードの状態を決める（docs/PREGNANCY_MODE.md の「妊娠中に止める機能」「モードの終わり方」）。
    ///
    /// - Parameters:
    ///   - isFemale: プロフィールの性別が女性か（女性でなければ、モードは使われない）
    ///   - hasActivePlan: モード中の設定があるか
    ///   - lastEndedAt: いちばん最近に終えたモードの、終えた日時
    ///   - goalStartDate: 今の目標を決めた日時（目標がなければ nil）
    ///   - resumedEndedAt: 「前の目標に戻す」を押したときの、そのモードの終えた日時（押していなければ nil）
    static func modeState(
        isFemale: Bool,
        hasActivePlan: Bool,
        lastEndedAt: Date?,
        goalStartDate: Date?,
        resumedEndedAt: Date?
    ) -> PregnancyModeState {
        guard isFemale else { return .off }
        if hasActivePlan { return .active }
        guard let lastEndedAt, let goalStartDate, goalStartDate < lastEndedAt else { return .off }
        // 「前の目標に戻す」を押したのが、このモードの終わりについてなら、ふだんどおり（1 秒の誤差は同じとみなす）
        if let resumedEndedAt, abs(resumedEndedAt.timeIntervalSince(lastEndedAt)) < 1 {
            return .off
        }
        return .goalPausedAfterPregnancy
    }
}
