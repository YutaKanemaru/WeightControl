import SwiftUI
import SwiftData

/// アプリのいちばん外側の画面。
///
/// プロフィールがまだ保存されていなければ「はじめに」（初回設定）を、
/// 保存されていればタブ画面を表示します。
/// 初回設定で保存した瞬間に `@Query` の結果が変わるので、自動でタブ画面に切り替わります。
struct RootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .animation(.default, value: profiles.isEmpty)
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
