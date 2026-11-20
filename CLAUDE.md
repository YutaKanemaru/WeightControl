# CLAUDE.md

このファイルは、AI アシスタント（Claude）がこのリポジトリで作業するときのルールです。人間の開発者が読んでも分かるように書いています。

## プロジェクト概要

体重管理 iOS アプリ（SwiftUI + SwiftData）。詳細な機能は README.md を参照。

## コミュニケーション

- 開発者は iOS 開発の初心者。説明・PR 本文・コミットの説明は**日本語**で、「なぜそうするのか」「どう動くのか」を添える。
- 専門用語は初出時に一言で説明する。

## 技術方針

- **Apple 純正フレームワークのみ**（SwiftUI / SwiftData / HealthKit / UserNotifications / Swift Charts / WidgetKit / WatchKit）。外部ライブラリは相談なしに追加しない。
- データは**端末内のみ**（SwiftData）。外部サーバーへの送信はしない。
- 対応 OS は `IPHONEOS_DEPLOYMENT_TARGET` に従う（現在 iOS 26.0）。iOS 27 で追加された API を使うときは `if #available(iOS 27, *)` で分岐する。
- プロジェクトファイルは Xcode のフォルダ同期方式（`project.xcproj`）。`WeightControlApp/` 配下にファイルを置けば自動でターゲットに入るので、ファイル追加のためにプロジェクトファイルを編集する必要はない。
- 既定のアクター分離は `MainActor`（`SWIFT_DEFAULT_ACTOR_ISOLATION`）。重い計算を別スレッドで行う場合は `nonisolated` や `@concurrent` を明示する。

## フォルダの役割

| フォルダ | 置くもの | ルール |
|---|---|---|
| `WeightControlApp/App/` | `@main` のアプリ本体、ModelContainer の設定 | 小さく保つ |
| `WeightControlApp/Models/` | `@Model` のデータ型 | 保存する「形」だけ。計算は Logic へ |
| `WeightControlApp/Views/` | SwiftUI の画面・部品 | 計算ロジックを直接書かない |
| `WeightControlApp/Logic/` | 予測（実測体重への線形回帰。EMA はグラフ用）、カロリー計算（Mifflin-St Jeor）、メッセージ生成など。`Food/`・`Messages/`・`Calendar/`・`Health/`・`Reminders/`・`Demo/` のサブフォルダあり | **SwiftUI / SwiftData に依存しない純粋な関数・struct**（`nonisolated` を付ける）。必ずテストを書く |
| `WeightControlApp/Services/` | HealthKit・通知（UserNotifications）など、外の仕組みとやり取りする窓口と、その結果を SwiftData に反映する係 | 外の型（`HKQuantitySample` など）はここで値の型に変換し、判断のルールは `Logic/` に置いてテストする |
| `WeightControlApp/Resources/` | アプリに同梱するデータ（`FoodCalories.json`） | 数値の修正はコードではなく JSON で |
| `WeightControlAppTests/` | Swift Testing の単体テスト | `Logic/` のテストが中心 |
| `WeightControlAppUITests/` | XCTest の UI テスト | 主要な画面遷移だけ |

## コーディング規約

- Swift API Design Guidelines に従う。型は `UpperCamelCase`、変数・関数は `lowerCamelCase`。
- 体重は `Double`（kg）、日付は `Date`。単位を変数名かコメントで明示する（例: `weightKg`）。
- ユーザー向けの文言は日本語。String Catalog（`Localizable.xcstrings`）で管理する。
- メッセージは「ほめる」を優先し、責める表現を使わない。
- 医療的な断定をしない。必要な画面には「医療アドバイスではありません」の免責表示を出す。

## UI の見た目の方針

Apple の「ワークアウト」アプリのような、**シンプルで、運動中でもひと目で読める** 雰囲気を目指す。

- Apple の Human Interface Guidelines（HIG：Apple が公開している画面づくりの指針）に沿い、SwiftUI の標準の部品（`List`・`Form`・`NavigationStack`・`Chart` など）を基本にする。
- いちばん伝えたい数字（体重・目標まで・摂取カロリーの目安など）は **大きく太く**、`monospacedDigit()` で桁がずれないようにする。説明文は小さく控えめに。
- 情報は角丸の **カード** に分けて縦に並べる（ホームの `DashboardCard` を使い回す）。1 枚のカードに詰め込みすぎない。
- アイコンは **SF Symbols**（Apple が無料で提供するアイコン集）を使う。色はアクセントカラーと、意味のある色（達成＝緑、注意＝オレンジなど）に絞る。
- **ダークモード** と **Dynamic Type**（文字サイズの設定）で崩れないようにする。色は `.primary` / `.secondary` / `.background` などのシステムの色を使い、固定の色を直接書かない。
- **まねしないこと**：Apple の画面をそのまま写さない。アクティビティリング（3 色の輪）など Apple 独自のデザインやアイコン、Apple のロゴ・アプリ名は使わない。Apple 公式アプリや Apple と提携していると誤解される見た目・文言にしない（App Store の審査でも問題になるため）。

## 現在の状態

- 進み具合は `docs/ROADMAP.md` が正。作業を始める前に読み、PR でフェーズが進んだら更新する。
- フェーズ 1〜7 は画面まで完成（フェーズ 3〜5 はホームタブ。`HomeDashboardBuilder` が既存ロジックをまとめる）。フェーズ 8 は記録のリマインド通知まで。
- 予測・安全チェック・カロリーの「今の体重」は、直近 21 日の測った体重に引いた直線の今日の値（`GoalForecaster.paceEstimate`）。EMA（`WeightTrendCalculator`）はグラフの線とほめるメッセージだけに使い、画面に「トレンド」という言葉や数字は出さない。
- 消費カロリーは `EnergyExpenditureResolver` が「自動（ヘルスケアの実績 7 日分以上なら実績、なければ活動係数）・活動量・ヘルスケアの実績」から決める。
- 予測やカロリーの計算を変えたら、`DemoScenarioTests` と `docs/DEMO_DATA.md`（デモデータの期待値）も同じ PR で更新する。
- 予測の幅（楽観〜悲観）は Pro 機能（フェーズ 12）で作る。それまでは 1 本の予測だけ。
- ロジックの入力は `SwiftData` の型ではなく `WeightPoint` などの値の型を使う。カロリー計算の `BiologicalSex` / `ActivityLevel` は `UserProfile.Sex` / `UserProfile.ActivityLevel` とは別の型なので、画面側で変換する。

## テスト

- テストフレームワークは **Swift Testing**（`import Testing`、`@Test`、`#expect`）。
- `Logic/` に関数を追加・変更したら、同じ PR でテストを追加・更新する。
- ローカルでは Xcode の `⌘U`、CI では `xcodebuild test`（`.github/workflows/ci.yml`、`runs-on: xcode-27`）。
- クラウドの作業環境には Swift のツールがないので、ビルドとテストの確認は PR の CI で行う。

## Git の運用

- `main` に直接 push しない。作業ブランチ（例: `feature/weight-entry`、`fix/graph-crash`）を切って PR を出す。
- コミットは小さく、メッセージは何をしたかが分かるように書く。
- `xcuserdata/` などの個人設定はコミットしない（`.gitignore` 済み）。
- `Localizable.xcstrings` はビルド時に Xcode が自動で文字列を書き足す。これは**コミットする**（画面の文言を足したら、同じ PR に含める）。

### 開発の流れ

1. Claude が作業ブランチを切り、GitHub に PR を出す（Claude は PR をマージしない）。
2. CI（GitHub Actions）がビルドと単体テストを実行する。
3. 開発者が PR を確認して GitHub 上でマージする。
4. 開発者の Mac で pull する（Xcode の **Integrate → Pull…**、または Claude に頼む）。

- コミットの作者メールは GitHub の noreply アドレス（`48906469+YutaKanemaru@users.noreply.github.com`）を使う。公開リポジトリに個人のメールアドレスを残さないため。
