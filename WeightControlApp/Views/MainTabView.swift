import SwiftUI
import SwiftData

/// 画面下のタブ（TabView）。タブごとに別の画面を切り替えて表示します。
///
/// 今後のフェーズで「グラフ」「カレンダー」などのタブをここに追加していきます。
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("ホーム", systemImage: "house") {
                HomeView()
            }
            Tab("記録", systemImage: "list.bullet") {
                WeightHistoryView()
            }
            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(.preview())
}
