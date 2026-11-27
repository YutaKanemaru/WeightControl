import SwiftUI

/// Apple Watch アプリの入り口（`@main`）。仕様は docs/WATCH.md。
///
/// Watch アプリは iPhone アプリとは別のプログラムとして Watch の上で動きます。
/// 数字の計算はせず、iPhone から届いたスナップショット（ホーム・ウィジェットと同じ数字）を表示し、
/// 記録した体重を iPhone に送るだけにしています。
@main
struct WeightForecastWatchApp: App {
    /// iPhone とやりとりする係。アプリで 1 つだけ作り、environment で画面に渡す
    @State private var connection = PhoneConnection()

    var body: some Scene {
        WindowGroup {
            WatchSummaryView()
                .environment(connection)
        }
    }
}
