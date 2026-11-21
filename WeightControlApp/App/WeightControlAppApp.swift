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
    /// 型を追加しても、すでに保存されている体重の記録はそのまま残ります（SwiftData が自動で移行します）。
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WeightEntry.self,
            UserProfile.self,
            WeightGoal.self,
            ExerciseDay.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// ヘルスケア連携の係。アプリ全体で 1 つだけ作り、environment（画面の「共有の持ち物」）で各画面に渡します。
    @State private var healthSync = HealthSyncController()
    /// Pro 機能を使えるかどうかの係（今は Debug ビルドの「Pro を試す」だけ。課金はフェーズ 11 で追加）
    @State private var proAccess = ProAccess()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(healthSync)
                .environment(proAccess)
        }
        .modelContainer(sharedModelContainer)
    }
}
