import Foundation

/// 食品カロリー表の 1 行分（例: りんご 中1個 = 約130kcal）。
///
/// アプリに同梱した `Resources/FoodCalories.json` から読み込みます。
/// `Decodable`（デコーダブル）は「JSON などから自動で組み立てられる型」という意味です。
nonisolated struct FoodItem: Decodable, Equatable, Sendable, Identifiable {
    /// 英数字の識別子（例: "apple"）。表示には使いません。
    var id: String
    /// 表示名（例: "りんご"）
    var name: String
    /// 数えるときの単位（例: "個"、"本"、"杯"）
    var unit: String
    /// 1 単位がどのくらいの量か（例: "中1個（約250g）"）。詳しく見せたいとき用。
    var portion: String
    /// 1 単位あたりのカロリー（kcal）。おおよその目安です。
    var kcal: Double
    /// 種類（くだもの・お酒など）。「お酒は候補から外す」といった絞り込みに使います。
    var category: FoodCategory
}

/// 食品の種類
nonisolated enum FoodCategory: String, Decodable, Sendable, CaseIterable {
    /// くだもの
    case fruit
    /// ごはん・パン・麺などの主食
    case staple
    /// おかず・軽食
    case dish
    /// スナック菓子
    case snack
    /// 甘いもの
    case sweets
    /// ソフトドリンク
    case drink
    /// お酒
    case alcohol
}
