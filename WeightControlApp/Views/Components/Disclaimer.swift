import SwiftUI

// 免責表示（「医療アドバイスではありません」「ご利用は自己責任で」）の共通部品。
//
// 文言を 1 か所にまとめておくと、初回設定・設定タブ・ヘルスケア画面で言い方がばらばらにならず、
// あとで直すときも 1 か所で済みます。

/// 画面の下（Form の Section の footer など）に出す、短い免責の一文。
struct DisclaimerFooter: View {
    var body: some View {
        NoticeLabel("このアプリは医療アドバイスではありません。表示する数値は目安です。ご利用は自己責任でお願いします。")
    }
}

/// 免責の内容を、アイコン付きの箇条書きでくわしく見せる部品。初回設定と「ご利用にあたって」の画面で使います。
struct DisclaimerPoints: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoPointRow(
                title: "医療アドバイスではありません",
                detail: "体重の予測やカロリーの目安は、一般的な計算式から出した参考の数値です。診断や治療の代わりにはなりません。",
                systemImage: "stethoscope"
            )
            InfoPointRow(
                title: "体調をいちばんに",
                detail: "持病のある方、妊娠中・授乳中の方、成長期の方は、始める前に医師に相談してください。体調に不安を感じたら、無理をせず休みましょう。",
                systemImage: "heart"
            )
            InfoPointRow(
                title: "ご利用は自己責任で",
                detail: "アプリの表示を参考にするかどうかは、ご自身で判断してください。",
                systemImage: "hand.raised"
            )
            InfoPointRow(
                title: "データはこの iPhone の中だけ",
                detail: "入力した情報は端末の中に保存し、外部のサーバーには送りません。",
                systemImage: "lock.iphone"
            )
        }
    }
}

#Preview("箇条書き") {
    ScrollView {
        DisclaimerPoints()
            .padding()
    }
}

#Preview("footer・大きい文字・ダークモード") {
    Form {
        Section {
            Text(verbatim: "…")
        } footer: {
            DisclaimerFooter()
        }
    }
    .dynamicTypeSize(.accessibility2)
    .preferredColorScheme(.dark)
}
