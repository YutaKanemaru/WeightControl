import SwiftUI
import SwiftData

/// 設定タブの「妊娠中の方へ」の欄。プロフィールの性別が女性のときだけ出します（docs/PREGNANCY_MODE.md）。
///
/// 性別だけで「妊娠しているかも」と決めつけないように、本人が「始める」を押したときだけモードになります。
struct PregnancySettingsSection: View {
    @Query(sort: \PregnancyPlan.startedAt, order: .reverse) private var plans: [PregnancyPlan]
    /// 身長（cm）。妊娠前の BMI に使う
    let heightCm: Double

    var body: some View {
        Section {
            if let plan = plans.activePlan {
                NavigationLink {
                    PregnancyPlanSettingsView(plan: plan, heightCm: heightCm)
                } label: {
                    activeSummary(plan)
                }
                .accessibilityHint(Text("妊娠中モードの設定を変えます"))
            } else {
                NavigationLink {
                    PregnancyStartView(heightCm: heightCm)
                } label: {
                    Label("妊娠中モードを始める", systemImage: "figure.and.child.holdinghands")
                }
            }
        } header: {
            Text("妊娠中の方へ")
        } footer: {
            Text("妊娠中は、減量のための機能を止めて、妊娠前の体格に合った体重の増え方の目安と、ご自身の記録を並べて見られます。無料で使えます。")
        }
    }

    private func activeSummary(_ plan: PregnancyPlan) -> some View {
        let age = GestationalAgeCalculator.age(dueDate: plan.dueDate, on: .now)
        return VStack(alignment: .leading, spacing: 6) {
            Label("妊娠中モード", systemImage: "figure.and.child.holdinghands")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            MetricView(
                "今日",
                text: gestationalAgeText(age),
                caption: Text("出産予定日 \(plan.dueDate, format: .dateTime.year().month().day())"),
                size: .medium
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// 妊娠中モードを始める画面：入力欄と、始める前の確認。
struct PregnancyStartView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    let heightCm: Double

    @State private var draft = PregnancyPlanDraft()
    /// 入力のまちがいを見せるか（「始める」を押してから出す）
    @State private var showsErrors = false

    var body: some View {
        Form {
            PregnancyPlanFormSections(draft: $draft, heightCm: heightCm, preWeightSuggestionKg: preWeightSuggestionKg)

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    InfoPointRow(
                        title: "健診で言われたことを優先",
                        detail: "この目安は公的な資料をもとにした一般的なものです。健診で言われた目安があれば、そちらを優先してください。18 歳未満の方は、とくに医師に相談しながら使ってください。",
                        systemImage: "stethoscope"
                    )
                    InfoPointRow(
                        title: "増え方には個人差があります",
                        detail: "目安から外れても、それだけで心配する必要はありません。気になることは健診で相談しましょう。",
                        systemImage: "person.2"
                    )
                    InfoPointRow(
                        title: "気になる変化は早めに相談",
                        detail: "急に体重が増えた、むくみが強い、体調がおかしいなど、気になる変化があれば、健診を待たずにかかりつけの医療機関に相談してください。",
                        systemImage: "phone"
                    )
                    InfoPointRow(
                        title: "減量のための機能を止めます",
                        detail: "妊娠中は食事を減らすダイエットはしないでください。このモードの間は、目標・予測・カロリーの目安・チートデーなどを出しません。",
                        systemImage: "pause.circle"
                    )
                    InfoPointRow(
                        title: "データはこの iPhone の中だけ",
                        detail: "外には送りません。通知とウィジェットには「妊娠」という言葉を出しません。",
                        systemImage: "lock.iphone"
                    )
                    InfoPointRow(
                        title: "医療アドバイスではありません",
                        detail: "表示する数字は目安です。体調をいちばんに、無理をしないでください。",
                        systemImage: "heart"
                    )
                }
                .padding(.vertical, 4)

                Button {
                    start()
                } label: {
                    Text("確認して始める")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            } header: {
                Text("始める前にご確認ください")
            } footer: {
                if showsErrors, !draft.isValid {
                    FieldErrorText(String(localized: "上の入力を確かめてください。"))
                }
            }
        }
        .navigationTitle("妊娠中モード")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 妊娠 0 週より前の 30 日の記録の平均（予定日が変わると候補も変わる）
    private var preWeightSuggestionKg: Double? {
        PregnancyAdvisor.prePregnancyWeightSuggestion(
            points: entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) },
            dueDate: draft.resolvedDueDate()
        )
    }

    private func start() {
        guard draft.isValid, case .success(let preWeightKg) = draft.preWeightResult else {
            showsErrors = true
            return
        }
        let plan = PregnancyPlan(dueDate: draft.resolvedDueDate(), prePregnancyWeightKg: preWeightKg)
        draft.apply(to: plan)
        modelContext.insert(plan)
        try? modelContext.save()
        dismiss()
    }
}

/// 妊娠中モードの設定を変える画面と、「妊娠中モードを終える」ボタン。
struct PregnancyPlanSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    let plan: PregnancyPlan
    let heightCm: Double

    @State private var draft: PregnancyPlanDraft
    @State private var isConfirmingEnd = false

    init(plan: PregnancyPlan, heightCm: Double) {
        self.plan = plan
        self.heightCm = heightCm
        _draft = State(initialValue: PregnancyPlanDraft(plan: plan))
    }

    var body: some View {
        Form {
            PregnancyPlanFormSections(draft: $draft, heightCm: heightCm, preWeightSuggestionKg: preWeightSuggestionKg)

            Section {
                Button("妊娠中モードを終える", role: .destructive) {
                    isConfirmingEnd = true
                }
            } footer: {
                Text("いつでも終えられます。記録はそのまま残ります。終えたあと、前の目標はすぐには戻さず、ホームから立て直せます。")
            }
        }
        .navigationTitle("妊娠中モード")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    draft.apply(to: plan)
                    try? modelContext.save()
                    dismiss()
                }
                .disabled(!draft.isValid || draft == PregnancyPlanDraft(plan: plan))
            }
        }
        .confirmationDialog("妊娠中モードを終えますか？", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("終える", role: .destructive) {
                plan.endedAt = .now
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("記録はそのまま残ります。")
        }
    }

    private var preWeightSuggestionKg: Double? {
        PregnancyAdvisor.prePregnancyWeightSuggestion(
            points: entries.map { WeightPoint(date: $0.date, weightKg: $0.weightKg) },
            dueDate: draft.resolvedDueDate()
        )
    }
}

#Preview("始める") {
    NavigationStack {
        PregnancyStartView(heightCm: 160)
    }
    .modelContainer(.preview())
}

#Preview("設定（モード中）") {
    let container = ModelContainer.preview()
    let plan = PregnancyPlan(dueDate: Calendar.current.date(byAdding: .day, value: 120, to: .now)!, prePregnancyWeightKg: 52)
    container.mainContext.insert(plan)
    return NavigationStack {
        PregnancyPlanSettingsView(plan: plan, heightCm: 160)
    }
    .modelContainer(container)
}
