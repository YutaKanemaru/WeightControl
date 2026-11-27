import Foundation

/// デモデータで使うプロフィール（年齢は「読み込んだ年」から生まれ年を逆算するので、いつ読み込んでも同じ年齢になります）。
nonisolated struct DemoProfile: Equatable, Sendable {
    var heightCm: Double
    var ageYears: Int
    var sex: BiologicalSex
    var activityLevel: ActivityLevel
}

/// デモデータで使う目標。期限は「今日から何日後か」で持ちます。
nonisolated struct DemoGoal: Equatable, Sendable {
    /// 目標体重（kg）
    var targetWeightKg: Double
    /// 期限（今日から何日後か）
    var deadlineDaysFromToday: Int
    /// 目標を決めたときの体重（kg）
    var startWeightKg: Double
    /// キープモード（Pro）を何日前に始めたか。nil ならモードではない。
    var maintenanceStartDaysAgo: Int? = nil
}

/// デモデータで使う妊娠中モードの設定（日付へ当てはめたもの）
nonisolated struct DemoPregnancy: Equatable, Sendable {
    /// 出産予定日（その日の 0 時）
    var dueDate: Date
    /// 妊娠前の体重（kg）
    var prePregnancyWeightKg: Double
}

/// デモデータを「今日」を基準に日付へ当てはめた結果。保存（SwiftData）の形には依存しない、ただの値です。
nonisolated struct DemoDataSet: Equatable, Sendable {
    /// 体重の記録（古い順。最後が今日）
    var points: [WeightPoint]
    /// ホーム画面の計算に使うのと同じ形のプロフィール
    var profile: DashboardProfile
    /// ホーム画面の計算に使うのと同じ形の目標
    var goal: DashboardGoal
    /// 目標を決めた日（最初の記録の日）
    var goalStartDate: Date
    /// 運動スタンプを押す日（各日の 0 時）
    var exerciseDays: [Date]
    /// 妊娠中モードの設定。nil ならモードではない。
    var pregnancy: DemoPregnancy? = nil
}

/// 予測・カロリー計算を画面で確かめるための「デモデータ」のシナリオ。
///
/// 体重は日々のブレ（水分・食事など）をまねて、1 週間周期の小さな上下
/// （0, +0.3, −0.2, +0.1, −0.1, +0.2, −0.3 kg）を入れ、0.1 kg 単位に丸めた固定の値にしています。
/// 値を固定にしているので、毎回同じ結果になり、`docs/DEMO_DATA.md` の期待値と見比べられます。
///
/// 日付だけは「読み込んだ日」が最後の記録になるようにずらします（いつ読み込んでも「今日まで記録した」状態になる）。
nonisolated enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    /// 順調に減っていて、期限に間に合う
    case onTrack
    /// 横ばい（停滞期）。食べ物ヒントが出る
    case plateau
    /// 目標のペースが速すぎる。修正案が出て、カロリーは下限に合わせられる
    case tooAggressive
    /// 記録が 10 日分だけ。予測は「参考値」
    case fewRecords
    /// キープモード（Pro）。範囲の中だが少しずつ上がっていて「そろそろ端」
    case maintenance
    /// 妊娠中モード。妊娠 24 週 0 日で、増え方の目安の帯の中
    case pregnancy

    var id: String { rawValue }

    /// 記録する時刻（朝 7 時）
    static let recordHour = 7

    /// 画面に出す名前
    var title: String {
        switch self {
        case .onTrack: String(localized: "① 順調に減っている")
        case .plateau: String(localized: "② 横ばい（停滞期）")
        case .tooAggressive: String(localized: "③ 目標が速すぎる")
        case .fewRecords: String(localized: "④ 記録が 10 日だけ")
        case .maintenance: String(localized: "⑤ キープモード（Pro）")
        case .pregnancy: String(localized: "⑥ 妊娠中モード")
        }
    }

    /// 画面に出す説明
    var summary: String {
        switch self {
        case .onTrack: String(localized: "28 日分・週 0.5 kg ペースで減少。目標 68 kg・期限 70 日後")
        case .plateau: String(localized: "28 日分・70 kg 前後で横ばい。目標 66 kg・期限 120 日後")
        case .tooAggressive: String(localized: "21 日分・週 0.4 kg ペースで減少。目標 72 kg・期限 30 日後")
        case .fewRecords: String(localized: "10 日分・週 0.3 kg ペースで減少。目標 57 kg・期限 90 日後")
        case .maintenance: String(localized: "28 日分・55 kg に届いて 21 日前にモード開始、その後少しずつ増加。Pro をオンにして確認")
        case .pregnancy: String(localized: "28 日分・妊娠前 52 kg（160 cm）から週 0.3 kg ペースで増加。今日が妊娠 24 週 0 日")
        }
    }

    /// 体重（kg）。古い順で、最後が「今日」の記録です。
    var weightsKg: [Double] {
        switch self {
        case .onTrack:
            // 72.0 kg から週 −0.5 kg のペース ＋ 日々のブレ
            [72.0, 72.2, 71.7, 71.9, 71.6, 71.8, 71.3,
             71.5, 71.7, 71.2, 71.4, 71.1, 71.3, 70.8,
             71.0, 71.2, 70.7, 70.9, 70.6, 70.8, 70.3,
             70.5, 70.7, 70.2, 70.4, 70.1, 70.3, 69.8]
        case .plateau:
            // 70.0 kg のまま ＋ 日々のブレ
            [70.0, 70.3, 69.8, 70.1, 69.9, 70.2, 69.7,
             70.0, 70.3, 69.8, 70.1, 69.9, 70.2, 69.7,
             70.0, 70.3, 69.8, 70.1, 69.9, 70.2, 69.7,
             70.0, 70.3, 69.8, 70.1, 69.9, 70.2, 69.7]
        case .tooAggressive:
            // 82.0 kg から週 −0.4 kg のペース ＋ 日々のブレ
            [82.0, 82.2, 81.7, 81.9, 81.7, 81.9, 81.4,
             81.6, 81.8, 81.3, 81.5, 81.3, 81.5, 81.0,
             81.2, 81.4, 80.9, 81.1, 80.9, 81.1, 80.6]
        case .fewRecords:
            // 60.0 kg から週 −0.3 kg のペース ＋ 日々のブレ
            [60.0, 60.3, 59.7, 60.0, 59.7, 60.0, 59.4,
             59.7, 60.0, 59.4]
        case .maintenance:
            // 56.2 kg から 1 日 −0.2 kg で 55.0 kg に届き、そのあと 1 日 +0.05 kg ずつ増える ＋ 日々のブレ
            [56.2, 56.3, 55.6, 55.7, 55.3, 55.4, 54.7,
             55.0, 55.4, 54.9, 55.3, 55.1, 55.5, 55.1,
             55.4, 55.8, 55.3, 55.6, 55.5, 55.9, 55.4,
             55.8, 56.1, 55.6, 56.0, 55.9, 56.2, 55.8]
        case .pregnancy:
            // 56.0 kg（妊娠 20 週 1 日）から週 +0.3 kg のペース ＋ 日々のブレ
            [56.0, 56.3, 55.9, 56.2, 56.1, 56.4, 56.0,
             56.3, 56.6, 56.2, 56.5, 56.4, 56.7, 56.3,
             56.6, 56.9, 56.5, 56.8, 56.7, 57.0, 56.6,
             56.9, 57.2, 56.8, 57.1, 57.0, 57.3, 56.9]
        }
    }

    var profile: DemoProfile {
        switch self {
        case .onTrack: DemoProfile(heightCm: 170, ageYears: 35, sex: .male, activityLevel: .light)
        case .plateau: DemoProfile(heightCm: 158, ageYears: 35, sex: .female, activityLevel: .sedentary)
        case .tooAggressive: DemoProfile(heightCm: 175, ageYears: 35, sex: .male, activityLevel: .sedentary)
        case .fewRecords: DemoProfile(heightCm: 160, ageYears: 35, sex: .female, activityLevel: .light)
        case .maintenance: DemoProfile(heightCm: 160, ageYears: 35, sex: .female, activityLevel: .light)
        case .pregnancy: DemoProfile(heightCm: 160, ageYears: 35, sex: .female, activityLevel: .light)
        }
    }

    var goal: DemoGoal {
        switch self {
        case .onTrack: DemoGoal(targetWeightKg: 68.0, deadlineDaysFromToday: 70, startWeightKg: 72.0)
        case .plateau: DemoGoal(targetWeightKg: 66.0, deadlineDaysFromToday: 120, startWeightKg: 70.0)
        case .tooAggressive: DemoGoal(targetWeightKg: 72.0, deadlineDaysFromToday: 30, startWeightKg: 82.0)
        case .fewRecords: DemoGoal(targetWeightKg: 57.0, deadlineDaysFromToday: 90, startWeightKg: 60.0)
        // 期限は目標に届いた日（21 日前）。モード中は期限を使わない
        case .maintenance: DemoGoal(targetWeightKg: 55.0, deadlineDaysFromToday: -21, startWeightKg: 58.0, maintenanceStartDaysAgo: 21)
        // 妊娠前に決めていた目標（モード中は使わない）
        case .pregnancy: DemoGoal(targetWeightKg: 50.0, deadlineDaysFromToday: 60, startWeightKg: 52.0)
        }
    }

    /// 妊娠中モードの設定：出産予定日（今日から何日後か）と妊娠前の体重（kg）。モードでなければ nil。
    var pregnancySetup: (dueInDays: Int, prePregnancyWeightKg: Double)? {
        switch self {
        case .pregnancy: (dueInDays: 112, prePregnancyWeightKg: 52.0)
        default: nil
        }
    }

    /// `today` を最後の記録の日として、日付つきのデータを作ります。
    ///
    /// - 記録は毎日朝 7 時（`recordHour`）
    /// - 生まれ年 ＝ 今日の年 − 年齢（計算は「年」の差だけで年齢を出すので、いつ読み込んでも同じ年齢）
    /// - 期限 ＝ 今日の 0 時 ＋ `deadlineDaysFromToday` 日
    /// - 運動スタンプは 3 日に 1 回（カレンダーの見た目用。計算には使いません）
    func dataSet(today: Date, calendar: Calendar = .current) -> DemoDataSet {
        let weights = weightsKg
        let firstOffset = -(weights.count - 1)

        let points = weights.enumerated().map { index, weightKg in
            let day = DayMath.date(byAddingDays: firstOffset + index, to: today, calendar: calendar)
            let date = calendar.date(byAdding: .hour, value: Self.recordHour, to: day) ?? day
            return WeightPoint(date: date, weightKg: weightKg)
        }
        let exerciseDays = weights.indices
            .filter { $0 % 3 == 1 }
            .map { DayMath.date(byAddingDays: firstOffset + $0, to: today, calendar: calendar) }

        let profile = self.profile
        let goal = self.goal
        return DemoDataSet(
            points: points,
            profile: DashboardProfile(
                heightCm: profile.heightCm,
                birthYear: calendar.component(.year, from: today) - profile.ageYears,
                sex: profile.sex,
                activityLevel: profile.activityLevel
            ),
            goal: DashboardGoal(
                targetWeightKg: goal.targetWeightKg,
                deadline: DayMath.date(byAddingDays: goal.deadlineDaysFromToday, to: today, calendar: calendar),
                startWeightKg: goal.startWeightKg,
                startDate: DayMath.date(byAddingDays: firstOffset, to: today, calendar: calendar),
                maintenanceStartDate: goal.maintenanceStartDaysAgo.map {
                    DayMath.date(byAddingDays: -$0, to: today, calendar: calendar)
                }
            ),
            goalStartDate: DayMath.date(byAddingDays: firstOffset, to: today, calendar: calendar),
            exerciseDays: exerciseDays,
            pregnancy: pregnancySetup.map {
                DemoPregnancy(
                    dueDate: DayMath.date(byAddingDays: $0.dueInDays, to: today, calendar: calendar),
                    prePregnancyWeightKg: $0.prePregnancyWeightKg
                )
            }
        )
    }
}
