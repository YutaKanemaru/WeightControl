import SwiftUI
import WidgetKit

/// ウィジェットの拡張の入り口（`@main`）。仕様は docs/WIDGET.md。
///
/// ここに並べたウィジェットが、ホーム画面・ロック画面の「ウィジェットを追加」の一覧に出ます。
/// アプリ本体とは別のプログラムとして動くので、アプリの `@main`（`WeightControlAppApp`）とは別に入り口があります。
@main
struct WeightForecastWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeightSummaryWidget()
    }
}
