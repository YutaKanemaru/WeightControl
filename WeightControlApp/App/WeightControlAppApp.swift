//
//  WeightControlAppApp.swift
//  WeightControlApp
//
//  Created by 金丸悠汰 on 2026/11/20.
//

import SwiftUI
import SwiftData

@main
struct WeightControlAppApp: App {
    /// アプリ全体で使うデータベース（SwiftData の ModelContainer）。
    /// ここに登録した @Model の型が、端末内に保存されるようになります。
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WeightEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
