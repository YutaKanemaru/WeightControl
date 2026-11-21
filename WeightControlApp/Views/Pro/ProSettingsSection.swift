import SwiftUI
import SwiftData

/// 設定タブの「Pro」セクション：Pro の状態、「Pro について」（お試しを始める画面）、開発用のスイッチ。仕様は docs/PRO.md。
///
/// 開発用の項目は `#if DEBUG` で囲んでいるので、Xcode から実行したとき（Debug ビルド）だけ表示されます。
/// App Store に出す Release ビルドにはコードごと入らず、`ProAccess` 側でもスイッチの値を無視します（二重の守り）。
struct ProSettingsSection: View {
    @Environment(ProAccess.self) private var pro: ProAccess?
    @State private var isShowingOffer = false

    #if DEBUG
    /// 開発用：お試しの状態を切りかえて画面を確かめる
    private enum DebugTrialState: Hashable {
        case notStarted, active, endingSoon, ended
    }
    #endif

    var body: some View {
        Section {
            Button {
                isShowingOffer = true
            } label: {
                LabeledContent {
                    statusText
                } label: {
                    Label("Pro について", systemImage: "star.circle")
                }
            }
            .foregroundStyle(.primary)

            #if DEBUG
            if let pro {
                Toggle(isOn: Binding(
                    get: { pro.isDebugTrialOn },
                    set: { pro.setDebugTrial($0) }
                )) {
                    Label("Pro を試す（開発用）", systemImage: "hammer")
                }
                Menu {
                    Button("まだ始めていない") { setDebugTrial(.notStarted) }
                    Button("お試し中（今日から）") { setDebugTrial(.active) }
                    Button("お試し中（残り 2 日）") { setDebugTrial(.endingSoon) }
                    Button("お試し終了") { setDebugTrial(.ended) }
                } label: {
                    Label("お試しの状態を変える（開発用）", systemImage: "calendar.badge.clock")
                }
            }
            #endif
        } header: {
            Text("Pro")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("目標に届く日・見込みの幅・チートデーの提案が使えます。1 か月無料で試せて、自動で料金がかかることはありません。購入のしくみは準備中です。")
                #if DEBUG
                Text("開発用の項目は Debug ビルドだけに表示され、Release ビルドでは効きません。")
                #endif
            }
        }
        .sheet(isPresented: $isShowingOffer) {
            ProOfferView()
        }
    }

    private var statusText: Text {
        switch pro?.status() ?? .trialAvailable {
        case .purchased: Text("購入済み")
        case .trial(_, let daysLeft): Text("お試し中・あと \(daysLeft) 日")
        case .trialEnded: Text("お試し終了")
        case .trialAvailable: Text("1 か月無料")
        case .debugUnlocked: Text("開発用で使用中")
        }
    }

    #if DEBUG
    private func setDebugTrial(_ state: DebugTrialState) {
        guard let pro else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // 「Pro を試す」がオンだとお試しの状態が見えないので、切っておく
        pro.setDebugTrial(false)
        switch state {
        case .notStarted:
            pro.debugSetTrialStartDate(nil)
            UserDefaults.standard.set(false, forKey: ProPreferenceKey.trialOfferDismissed)
        case .active:
            pro.debugSetTrialStartDate(.now)
        case .endingSoon:
            // 1 か月前の 2 日後に始めた → 残り 2 日
            let start = calendar.date(byAdding: .month, value: -ProAccessPolicy.trialLengthMonths, to: today).map {
                DayMath.date(byAddingDays: 2, to: $0, calendar: calendar)
            }
            pro.debugSetTrialStartDate(start)
        case .ended:
            pro.debugSetTrialStartDate(calendar.date(byAdding: .month, value: -2, to: today))
        }
    }
    #endif
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
