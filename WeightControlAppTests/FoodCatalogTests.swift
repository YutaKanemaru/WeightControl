import Foundation
import Testing
@testable import WeightControlApp

/// 同梱の食品カロリー表（FoodCatalog）のテスト
struct FoodCatalogTests {

    @Test("同梱の JSON が読み込めて、数十件の食品が入っている")
    func loadsBundledFoods() throws {
        let foods = try FoodCatalog.loadBundledFoods()
        #expect(foods.count >= 30)
    }

    @Test("同梱の食品はすべて名前・単位があり、カロリーが現実的な範囲")
    func bundledFoodsAreValid() throws {
        let foods = try FoodCatalog.loadBundledFoods()
        for food in foods {
            #expect(!food.name.isEmpty, "\(food.id) の名前が空")
            #expect(!food.unit.isEmpty, "\(food.id) の単位が空")
            #expect((10...1500).contains(food.kcal), "\(food.id) のカロリーが範囲外: \(food.kcal)")
        }
    }

    @Test("同梱の食品の id に重複がない")
    func bundledFoodIDsAreUnique() throws {
        let foods = try FoodCatalog.loadBundledFoods()
        #expect(Set(foods.map(\.id)).count == foods.count)
    }

    @Test("コーディネーター例の定番食品（りんご・おにぎり・バナナ・缶ビール）が入っている")
    func containsStapleExamples() throws {
        let names = Set(try FoodCatalog.loadBundledFoods().map(\.name))
        for name in ["りんご", "おにぎり", "バナナ", "缶ビール"] {
            #expect(names.contains(name), "\(name) がない")
        }
    }

    @Test("JSON のデータから食品を組み立てられる")
    func decodesFromData() throws {
        let json = """
        {"version": 1, "foods": [
          {"id": "apple", "name": "りんご", "unit": "個", "portion": "中1個", "kcal": 130, "category": "fruit"}
        ]}
        """
        let foods = try FoodCatalog.foods(from: Data(json.utf8))
        #expect(foods == [FoodItem(id: "apple", name: "りんご", unit: "個", portion: "中1個", kcal: 130, category: .fruit)])
    }

    @Test("知らない種類（category）があれば読み込みエラーにする")
    func rejectsUnknownCategory() {
        let json = """
        {"foods": [{"id": "x", "name": "x", "unit": "個", "portion": "", "kcal": 10, "category": "unknown"}]}
        """
        #expect(throws: DecodingError.self) {
            try FoodCatalog.foods(from: Data(json.utf8))
        }
    }
}
