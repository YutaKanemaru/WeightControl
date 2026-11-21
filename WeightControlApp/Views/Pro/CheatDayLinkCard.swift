import SwiftUI

/// ホームから「ごほうびの日の計画」（Pro）へ進むためのカード。Pro を使えるときだけホームに出します。
struct CheatDayLinkCard: View {
    var body: some View {
        DashboardCard(title: "ごほうびの日", systemImage: "gift", badge: "Pro") {
            Text("ふだんの日を少しだけ控えめにして、飲み会などの日に多めに食べられる 1 週間の予算を立てます。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                CheatDayPlannerView()
            } label: {
                Label("計画を立てる", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    NavigationStack {
        CheatDayLinkCard()
            .padding()
    }
}
