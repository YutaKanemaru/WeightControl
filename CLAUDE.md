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
| `WeightControlApp/Logic/` | 予測（EMA・線形回帰）、カロリー計算（Mifflin-St Jeor）、メッセージ生成など。`Food/`・`Messages/`・`Calendar/`・`Health/` のサブフォルダあり | **SwiftUI / SwiftData に依存しない純粋な関数・struct**（`nonisolated` を付ける）。必ずテストを書く |
| `WeightControlApp/Services/` | HealthKit など、外の仕組みとやり取りする窓口と、その結果を SwiftData に反映する係 | 外の型（`HKQuantitySample` など）はここで値の型に変換し、判断のルールは `Logic/` に置いてテストする |
| `WeightControlApp/Resources/` | アプリに同梱するデータ（`FoodCalories.json`） | 数値の修正はコードではなく JSON で |
| `WeightControlAppTests/` | Swift Testing の単体テスト | `Logic/` のテストが中心 |
| `WeightControlAppUITests/` | XCTest の UI テスト | 主要な画面遷移だけ |

## コーディング規約

- Swift API Design Guidelines に従う。型は `UpperCamelCase`、変数・関数は `lowerCamelCase`。
- 体重は `Double`（kg）、日付は `Date`。単位を変数名かコメントで明示する（例: `weightKg`）。
- ユーザー向けの文言は日本語。String Catalog（`Localizable.xcstrings`）で管理する。
- メッセージは「ほめる」を優先し、責める表現を使わない。
- 医療的な断定をしない。必要な画面には「医療アドバイスではありません」の免責表示を出す。

## 現在の状態

- 進み具合は `docs/ROADMAP.md` が正。作業を始める前に読み、PR でフェーズが進んだら更新する。
- フェーズ 1〜7 は画面まで完成（フェーズ 3〜5 はホームタブ。`HomeDashboardBuilder` が既存ロジックをまとめる）。
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
