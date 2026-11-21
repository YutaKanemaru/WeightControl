import SwiftUI

/// 設定タブから開く「ご利用にあたって」の画面。
///
/// 初回設定で見せた注意（医療アドバイスではありません・自己責任・データは端末の中だけ）を、
/// いつでも読み返せるようにしています。最後にアプリのバージョンを出します。
struct AboutAppView: View {
    var body: some View {
        List {
            Section {
                DisclaimerPoints()
                    .padding(.vertical, 8)
            }

            Section {
                LabeledContent("バージョン", value: Self.versionText)
            } footer: {
                Text("広告の表示や、データの販売はしていません。")
            }
        }
        .navigationTitle("ご利用にあたって")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 「1.0（3）」のような表示。Info.plist の値から作る。
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version)（\(build)）"
    }
}

#Preview {
    NavigationStack {
        AboutAppView()
    }
}

#Preview("大きい文字・ダークモード") {
    NavigationStack {
        AboutAppView()
    }
    .dynamicTypeSize(.accessibility3)
    .preferredColorScheme(.dark)
}
