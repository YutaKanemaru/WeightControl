import Foundation

/// 同梱の食品カロリー表（`Resources/FoodCalories.json`）を読み込む役。
///
/// JSON の中身を直接いじれば、コードを変えずに食品を増やしたり数値を直したりできます。
nonisolated enum FoodCatalog {
    /// アプリに同梱している JSON のファイル名（拡張子なし）
    static let bundledResourceName = "FoodCalories"

    enum LoadError: Error, Equatable {
        /// アプリの中に JSON ファイルが見つからない
        case resourceNotFound
    }

    /// JSON ファイル全体の形。`foods` 以外（version・note）は人間向けのメモなので読み飛ばします。
    private struct FileContents: Decodable {
        var foods: [FoodItem]
    }

    /// JSON のデータ（バイト列）から食品の一覧を作ります。テストではこちらを直接使います。
    static func foods(from data: Data) throws -> [FoodItem] {
        try JSONDecoder().decode(FileContents.self, from: data).foods
    }

    /// アプリに同梱した JSON から食品の一覧を読み込みます。
    ///
    /// - Parameter bundle: 読み込み元のバンドル（アプリの「中身のフォルダ」）。ふだんは省略（nil）で OK。
    static func loadBundledFoods(bundle: Bundle? = nil) throws -> [FoodItem] {
        let bundle = bundle ?? Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: bundledResourceName, withExtension: "json") else {
            throw LoadError.resourceNotFound
        }
        return try foods(from: Data(contentsOf: url))
    }
}

/// 「このコードが入っているバンドル（＝アプリ本体）」を見つけるための目印のクラス。
/// テストから呼んだときもアプリ側の JSON を確実に見つけられるようにしています。
private nonisolated final class BundleToken {}
