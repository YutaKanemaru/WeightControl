import SwiftUI
import SwiftData

/// アプリのいちばん外側の画面。
///
/// プロフィールがまだ保存されていなければ「はじめに」（初回設定）を、
/// 保存されていればタブ画面を表示します。
/// 初回設定で保存した瞬間に `@Query` の結果が変わるので、自動でタブ画面に切り替わります。
struct RootView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    /// アプリが前面にあるか・裏に回ったか（scenePhase）
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthSyncController.self) private var health: HealthSyncController?

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .animation(.default, value: profiles.isEmpty)
        // アプリを開いたとき・前面に戻ったときに、ヘルスケアと同期する（連携がオンのときだけ）
        .task(id: scenePhase) {
            if scenePhase == .active, let health {
                await health.sync(context: modelContext)
            }
        }
        // 記録や通知の設定が変わったら、リマインド通知を作り直す
        .weighInReminderSync()
        // 記録や目標が変わったら、ホーム画面・ロック画面のウィジェットの数字を更新する（docs/WIDGET.md）
        .widgetSnapshotSync()
    }
}

#Preview("初回（プロフィールなし）") {
    RootView()
        .modelContainer(.preview(includesProfile: false))
}

#Preview("設定済み") {
    RootView()
        .modelContainer(.preview())
}
