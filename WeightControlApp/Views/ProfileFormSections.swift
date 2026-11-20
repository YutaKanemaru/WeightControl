import SwiftUI

/// プロフィール入力欄に入っている「編集中の値」。
///
/// 入力欄の文字列はまだ数字として正しいか分からないので、保存用の `UserProfile` とは別に持っておき、
/// 「保存」を押したときにチェックしてから `UserProfile` に書き込みます。
struct ProfileDraft {
    var heightText = ""
    var birthYear = 1990
    var sex: UserProfile.Sex = .female
    var activityLevel: UserProfile.ActivityLevel = .light

    init() {}

    /// 保存済みのプロフィールから、編集の出発点を作る
    init(profile: UserProfile) {
        heightText = profile.heightCm.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        birthYear = profile.birthYear
        sex = profile.sex
        activityLevel = profile.activityLevel
    }
}

/// プロフィールの入力欄（身長・生まれた年・性別・活動量）。
///
/// 初回設定（`OnboardingView`）と設定画面（`EditProfileView`）の両方で使う「部品」です。
/// `@Binding` は「親の画面が持っている値を、この部品から直接書き換えられるようにする」仕組みです。
struct ProfileFormSections: View {
    @Binding var draft: ProfileDraft
    /// 身長の入力エラー（なければ nil）
    let heightErrorMessage: String?

    private let selectableBirthYears = ProfileInputValidator.selectableBirthYears(on: .now)

    var body: some View {
        Section {
            HStack {
                TextField("身長", text: $draft.heightText, prompt: Text(verbatim: "170"))
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
                Text(verbatim: "cm")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("身長")
        } footer: {
            if let heightErrorMessage {
                Text(heightErrorMessage)
                    .foregroundStyle(.red)
            }
        }

        Section {
            Picker("生まれた年", selection: $draft.birthYear) {
                ForEach(selectableBirthYears, id: \.self) { year in
                    Text(verbatim: "\(year)").tag(year)
                }
            }
            Picker("性別", selection: $draft.sex) {
                ForEach(UserProfile.Sex.allCases) { sex in
                    Text(sex.title).tag(sex)
                }
            }
        } header: {
            Text("あなたについて")
        } footer: {
            let age = ProfileInputValidator.age(birthYear: draft.birthYear, on: .now)
            Text("今年 \(age) 歳。年齢と性別は、基礎代謝（何もしなくても使うカロリー）の計算に使います。")
        }

        Section {
            Picker("活動量", selection: $draft.activityLevel) {
                ForEach(UserProfile.ActivityLevel.allCases) { level in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.title)
                        Text(level.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(level)
                }
            }
            // 選択肢を別の画面に一覧で出す（説明文まで読めるように）
            .pickerStyle(.navigationLink)
        } header: {
            Text("ふだんの活動量")
        } footer: {
            Text("1 日に使うカロリーの目安を出すときに使います。あとから設定で変えられます。")
        }
    }
}

// MARK: - 選択肢の表示名

extension UserProfile.Sex {
    /// 画面に出す名前
    var title: LocalizedStringResource {
        switch self {
        case .male: "男性"
        case .female: "女性"
        }
    }
}

extension UserProfile.ActivityLevel {
    /// 画面に出す名前
    var title: LocalizedStringResource {
        switch self {
        case .sedentary: "ほとんど運動しない"
        case .light: "軽い運動をする"
        case .moderate: "よく運動する"
        case .active: "とてもよく運動する"
        case .veryActive: "非常に活発"
        }
    }

    /// 選ぶときの目安
    var detail: LocalizedStringResource {
        switch self {
        case .sedentary: "デスクワーク中心で、運動はほとんどしない"
        case .light: "週 1〜3 回、散歩などの軽い運動をする"
        case .moderate: "週 3〜5 回、ジョギングなどの運動をする"
        case .active: "ほぼ毎日、しっかり運動する"
        case .veryActive: "激しいトレーニングや、体を使う仕事をしている"
        }
    }
}

extension ProfileInputValidator.HeightError {
    /// 画面に出すエラーメッセージ
    var message: String {
        switch self {
        case .empty: String(localized: "身長を入力してください。")
        case .notANumber: String(localized: "数字で入力してください（例: 170）。")
        case .outOfRange: String(localized: "100〜250 cm の範囲で入力してください。")
        }
    }
}

#Preview {
    @Previewable @State var draft = ProfileDraft()
    NavigationStack {
        Form {
            ProfileFormSections(draft: $draft, heightErrorMessage: nil)
        }
    }
}
