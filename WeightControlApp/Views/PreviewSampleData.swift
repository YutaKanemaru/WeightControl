import Foundation
import SwiftData

/// Xcode のプレビュー（#Preview）専用のサンプルデータ。
///
/// メモリ上だけの一時的なデータベースを作るので、実際のアプリのデータには影響しません。
extension ModelContainer {
    static func preview(includesProfile: Bool = true, includesGoal: Bool = true) -> ModelContainer {
        let container = try! ModelContainer(
            for: WeightEntry.self, UserProfile.self, WeightGoal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let samples: [Double] = [65.0, 64.8, 64.9, 64.6, 64.5]
        for (daysAgo, weightKg) in samples.reversed().enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            context.insert(WeightEntry(date: date, weightKg: weightKg))
        }
        if includesProfile {
            context.insert(UserProfile(heightCm: 170, birthYear: 1990, sex: .male, activityLevel: .light))
        }
        if includesProfile && includesGoal {
            let deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now)!
            context.insert(WeightGoal(targetWeightKg: 62.0, deadline: deadline, startWeightKg: 65.0))
        }
        return container
    }
}
