import SwiftUI
import WidgetKit

/// Apple Watch のコンプリケーション（文字盤の小さな表示欄）の入り口。仕様は docs/WATCH.md の「コンプリケーションの種類」。
///
/// 中身ごとに別のコンプリケーションにしているので、文字盤の編集画面で、置き場所ごとに好きなものを選んで組み合わせられます。
@main
struct WatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        GoalRemainingComplication()
        DeadlineComplication()
        StreakComplication()
        SummaryComplication()
    }
}
