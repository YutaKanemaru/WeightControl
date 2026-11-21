import SwiftUI
import SwiftData

/// 設定タブの「Pro」セクション：Pro の状態と、開発用の「Pro を試す」スイッチ。
///
/// 「Pro を試す」は `#if DEBUG` で囲んでいるので、Xcode から実行したとき（Debug ビルド）だけ表示されます。
/// App Store に出す Release ビルドにはコードごと入らず、`ProAccess` 側でもスイッチの値を無視します（二重の守り）。
struct ProSettingsSection: View {
    @Environment(ProAccess.self) private var pro: ProAccess?

    var body: some View {
        Section {
            LabeledContent {
                statusText
            } label: {
                Label("Pro", systemImage: "star.circle")
            }

            #if DEBUG
            if let pro {
                Toggle(isOn: Binding(
                    get: { pro.isDebugTrialOn },
                    set: { pro.setDebugTrial($0) }
                )) {
                    Label("Pro を試す（開発用）", systemImage: "hammer")
                }
            }
            #endif
        } header: {
            Text("Pro")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("ホームのグラフの「見込みの幅」、チートデーの提案、キープモードが使えます。チートデーは、予定より先に進んでいるときにホームでアプリが提案します。キープモードは、目標に届いたあとに体重を範囲の中にキープするモードです。購入のしくみは準備中です。")
                #if DEBUG
                Text("「Pro を試す」は Debug ビルドだけに表示され、Release ビルドでは効きません。")
                #endif
            }
        }
    }

    private var statusText: Text {
        guard let pro, pro.isUnlocked else { return Text("準備中") }
        return pro.isPurchased ? Text("購入済み") : Text("お試し中")
    }
}

#Preview {
    NavigationStack {
        List {
            ProSettingsSection()
        }
    }
    .environment(ProAccess())
    .modelContainer(.preview())
}
