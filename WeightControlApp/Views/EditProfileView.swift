import SwiftUI
import SwiftData

/// 設定画面から開く、プロフィールの編集画面。
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    /// 編集する保存済みのプロフィール。
    /// SwiftData の `@Model` は、プロパティを書き換えるだけで自動的に保存されます。
    let profile: UserProfile

    @State private var draft: ProfileDraft
    @State private var heightErrorMessage: String?

    init(profile: UserProfile) {
        self.profile = profile
        // `@State` の最初の値を、保存済みのプロフィールから作る
        _draft = State(initialValue: ProfileDraft(profile: profile))
    }

    var body: some View {
        Form {
            ProfileFormSections(draft: $draft, heightErrorMessage: heightErrorMessage)
        }
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        .onChange(of: draft.heightText) { heightErrorMessage = nil }
    }

    private func save() {
        switch ProfileInputValidator.parseHeightCm(draft.heightText) {
        case .success(let heightCm):
            profile.heightCm = heightCm
            profile.birthYear = draft.birthYear
            profile.sex = draft.sex
            profile.activityLevel = draft.activityLevel
            profile.updatedAt = .now
            dismiss()
        case .failure(let error):
            heightErrorMessage = error.message
        }
    }
}

#Preview {
    let profile = UserProfile(heightCm: 170, birthYear: 1990, sex: .male, activityLevel: .light)
    NavigationStack {
        EditProfileView(profile: profile)
    }
    .modelContainer(.preview())
}
