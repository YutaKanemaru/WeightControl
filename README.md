# WeightControl（体重管理アプリ）

毎日の体重を記録して、目標体重までの道のりを「予測」と「ほめる言葉」で支える iOS アプリです。

> ⚠️ このアプリは医療アドバイスではありません。体調や減量のペースについては医師などの専門家に相談し、ご自身の責任でご利用ください。

## 主な機能と進み具合

✅ = 使える ／ 🧮 = 計算ロジックとテストはできていて、画面はこれから ／ ⬜ = 未着手

| 機能 | 状態 |
|---|---|
| 体重の記録・履歴一覧・前回からの増減・スワイプで削除 | ✅ |
| 初回のプロフィール入力（オンボーディング）、設定タブでの変更 | ✅ |
| 目標体重と期限の設定 | ✅ |
| 免責表示（設定タブ） | ✅ |
| 達成できそうかの予測（EMA トレンド＋線形回帰） | 🧮 |
| 体重グラフ（実績＋目標までの予測を点線で表示） | 🧮（点線の座標計算まで） |
| 推奨摂取カロリーの計算（Mifflin-St Jeor 式＋運動量） | 🧮 |
| 無理な目標のときに、現実的な期限・目標を提案 | 🧮 |
| 「ほめる」を優先したメッセージ | 🧮 |
| 食べ物ベースのカロリーオーバーのヒント（40 品目の食品表） | 🧮 |
| カレンダー（運動した日・体重を測った日にスタンプ、連続記録日数） | ✅ |
| ヘルスケア（HealthKit）連携：体重の取り込み・書き込み、運動した日の自動スタンプ、活動量の目安 | ✅ |
| 通知 | ⬜ |
| Apple Watch 対応 | ⬜ |

データはすべて端末内（SwiftData）に保存し、外部のサーバーには送りません。

開発の順番は [docs/ROADMAP.md](docs/ROADMAP.md) を参照してください。

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
│   │   ├── Food/                 ← 食品表の読み込み、食べ物ヒント
│   │   ├── Messages/             ← ほめるメッセージ、連続記録日数
│   │   ├── Calendar/             ← カレンダーのマス目、スタンプの集計
│   │   └── Health/               ← ヘルスケア連携のルール（重複防止、運動した日の判定、活動量の目安）
│   ├── Services/                 ← 外部の仕組み（HealthKit など）とのやり取り
│   ├── Resources/                ← アプリに同梱するデータ（FoodCalories.json：食品のカロリー表）
│   ├── Localizable.xcstrings     ← 画面の文言の一覧（String Catalog）
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

## 主なデータ（Models/）

| 型 | 保存するもの |
|---|---|
| `WeightEntry` | 体重（kg）と記録日時。ヘルスケアと同期した記録は、ヘルスケア側の ID と「取り込んだ記録か」も持つ |
| `UserProfile` | 身長（cm）、生まれた年、性別、活動量 |
| `WeightGoal` | 目標体重（kg）、期限、開始日、開始時の体重 |
| `ExerciseDay` | 運動した日（カレンダーの運動スタンプ）。手動か HealthKit からか、運動した分数（HealthKit 用） |

## 開発の進め方

いつもの流れは次のとおりです。

1. **Claude が作業ブランチを作り、GitHub に Pull Request（PR）を出す**
   PR は「この変更を `main` に取り込んでいいですか？」というお願いのことです。
2. **CI が自動でチェックする**
   CI（継続的インテグレーション）は、GitHub の Mac 上で自動的にビルドと単体テストを走らせる仕組みです（`.github/workflows/ci.yml`）。PR の画面に ✅ が付けば OK。
3. **Yuta が PR の内容を見て、GitHub 上で Merge する**
4. **Mac の手元にも反映する（pull）**
   Xcode の **Integrate → Pull…** を使うか、Claude に「Mac で pull して」と頼みます。

そのほかのルール:

- `main` ブランチには直接コミットしません。
- 計算ロジック（`Logic/`）には必ずテストを書きます。
- `Localizable.xcstrings` は、ビルドすると Xcode が画面の文字列を自動で書き足します。この変更は**コミットして残します**（未コミットのままだとブランチの切り替えや pull の邪魔になるため）。
- コミットの作者メールアドレスには、GitHub の noreply アドレス（`48906469+YutaKanemaru@users.noreply.github.com`）を使います。公開リポジトリなので、個人のメールアドレスが履歴に残らないようにするためです。
