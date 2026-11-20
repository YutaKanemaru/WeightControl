# WeightControl（体重管理アプリ）

毎日の体重を記録して、目標体重までの道のりを「予測」と「ほめる言葉」で支える iOS アプリです。

> ⚠️ このアプリは医療アドバイスではありません。体調や減量のペースについては医師などの専門家に相談し、ご自身の責任でご利用ください。

## 主な機能（予定）

- 体重の記録（HealthKit 連携）
- 目標体重と期限の設定、達成できそうかの予測（EMA トレンド＋線形回帰）
- 無理な目標の場合は、現実的なペースへの修正を提案
- 推奨摂取カロリーの計算（Mifflin-St Jeor 式＋運動量の傾向）
- 体重グラフ（実績＋目標までの予測を点線で表示）
- カレンダー（運動した日・体重を測った日にスタンプ）
- 「ほめる」を優先したメッセージと通知
- 食べ物ベースのカロリーオーバーのヒント（アプリ内の小さな食品表）
- Apple Watch 対応（あとで）

データはすべて端末内（SwiftData）に保存し、外部のサーバーには送りません。

## 開発環境

| 項目 | 内容 |
|---|---|
| Xcode | 27.2 以降 |
| 対応 OS | iOS 26.0 以降（`IPHONEOS_DEPLOYMENT_TARGET`） |
| UI | SwiftUI |
| データ保存 | SwiftData |
| テスト | Swift Testing（単体テスト）、XCTest（UI テスト） |
| 外部ライブラリ | なし（Apple 純正フレームワークのみ） |

## フォルダ構成

```
WeightControl/                    ← リポジトリのルート
├── WeightControlApp.xcodeproj    ← Xcode で開くのはこれ
├── WeightControlApp/             ← アプリ本体のソースコード
│   ├── App/                      ← アプリの入口（@main）と全体の設定
│   ├── Models/                   ← SwiftData で保存するデータの形（@Model）
│   ├── Views/                    ← 画面（SwiftUI の View）
│   ├── Logic/                    ← 計算ロジック（予測・カロリー計算など。画面に依存しない）
│   └── Assets.xcassets           ← アイコン・色・画像
├── WeightControlAppTests/        ← 単体テスト（Swift Testing）
├── WeightControlAppUITests/      ← UI テスト（XCTest）
└── .github/workflows/ci.yml      ← GitHub 上で自動ビルド＆テストする設定
```

このプロジェクトは Xcode の「フォルダ同期」方式を使っているので、`WeightControlApp/` の下にファイルやフォルダを追加すると、Xcode のプロジェクトにも自動で反映されます。

## はじめかた

1. このリポジトリを Mac に持ってくる（Xcode の **Integrate → Clone…**、または `git clone https://github.com/YutaKanemaru/WeightControl.git`）
2. `WeightControlApp.xcodeproj` をダブルクリックして Xcode で開く
3. 上部のデバイス選択でシミュレーター（例: iPhone）を選び、`⌘R` で実行
4. `⌘U` でテストを実行

## 開発の進め方

- `main` ブランチには直接コミットせず、作業ごとにブランチを作って Pull Request（PR）で取り込みます。
- PR を出すと GitHub Actions が自動でビルドと単体テストを実行します。
- 計算ロジック（`Logic/`）には必ずテストを書きます。
