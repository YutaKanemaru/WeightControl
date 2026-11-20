import Foundation

/// 履歴の一覧を「月ごと」のまとまり（セクション）に分けるロジック。
///
/// 記録が増えても見たい時期を探しやすいように、「2026年11月」のような見出しで区切ります。
nonisolated enum WeightHistorySections {
    /// 1 か月分のまとまり
    struct Section: Equatable, Sendable {
        /// その月の 1 日 0 時
        var monthStart: Date
        /// その月に入る記録の、元の配列での位置（並び順は元のまま）
        var indices: [Int]
    }

    /// 日付の一覧を月ごとに分けます。
    ///
    /// - 引数の並び順（一覧画面では新しい順）を崩さず、月が変わるところで区切ります。
    /// - 同じ月の記録が離れた位置にあっても、最初に出てきたセクションにまとめます。
    static func byMonth(_ dates: [Date], calendar: Calendar = .current) -> [Section] {
        var sections: [Section] = []
        var positionByMonth: [Date: Int] = [:]
        for (index, date) in dates.enumerated() {
            let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
            if let position = positionByMonth[monthStart] {
                sections[position].indices.append(index)
            } else {
                positionByMonth[monthStart] = sections.count
                sections.append(Section(monthStart: monthStart, indices: [index]))
            }
        }
        return sections
    }
}
