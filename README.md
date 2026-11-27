# 体重予報（WeightControl）

毎日の体重を記録して、目標体重までの道のりを「予測」と「ほめる言葉」で支える iOS アプリです。

> ⚠️ このアプリは医療アドバイスではありません。体調や減量のペースについては医師などの専門家に相談し、ご自身の責任でご利用ください。

## 主な機能と進み具合

✅ = 使える ／ 🚧 = 途中まで ／ ⬜ = 未着手

| 機能 | 状態 |
|---|---|
| 体重の記録・履歴一覧・前回からの増減・スワイプで削除（前回と 2.0 kg 以上ちがうときは確認。同じ日の記録は平均して 1 日 1 点。[docs/WEIGHT_RECORDS.md](docs/WEIGHT_RECORDS.md)） | ✅ |
| 初回のプロフィール入力（オンボーディング）、設定タブでの変更 | ✅ |
| 目標体重と期限の設定（入力中に、無理のないペースかと、目標体重の BMI の目安を表示） | ✅ |
| 免責表示（初回設定と、設定タブの「ご利用にあたって」） | ✅ |
| 達成できそうかの予測（直近 3 週間の体重に線形回帰で直線を引き、今のペースと期限に間に合うかを表示。目標に届く日は Pro） | ✅ |
| 体重グラフ（測った体重の点＋直近 3 週間の直線＋目標までの予測を点線で表示。目標体重の横線と期限の縦線つき。記録 3 日から予測し、7 日未満は「精度は低め」と表示） | ✅ |
| 推奨摂取カロリーの計算（基礎代謝は Mifflin-St Jeor 式。消費カロリーは、ヘルスケアに 7 日分以上の実績があれば実績、なければ活動量から自動で切り替え。設定で手動選択も可） | ✅ |
| 無理な目標のときに、現実的な期限・目標を提案 | ✅ |
| 「ほめる」を優先したメッセージ | ✅ |
| 食べ物ベースのカロリーオーバーのヒント（40 品目の食品表） | ✅ |
| カレンダー（運動した日・体重を測った日にスタンプ、連続記録日数） | ✅ |
| ヘルスケア（HealthKit）連携：体重の取り込み・書き込み、運動した日の自動スタンプ、活動量の目安 | ✅ |
| 動作確認用のデモデータ（Debug ビルドの設定タブから読み込み。期待値は [docs/DEMO_DATA.md](docs/DEMO_DATA.md)） | ✅ |
| 記録のリマインド通知（時刻を設定、記録済みの日は出さない。初回設定でオンにするか聞く） | ✅ |
| ほめる通知（日曜の夜に 1 週間のふり返り、連続記録や目標の 25/50/75/100% のお祝い） | ✅ |
| 画面の作り直し（ワークアウトアプリのような、大きな数字とカードの見た目。ホーム・履歴・入力・カレンダー・設定・初回設定） | ✅ |
| Pro 機能：目標に届く日（日付とグラフの点線の予測）、予測の幅（「3 月 8 日〜4 月 2 日ごろ」とグラフの薄い帯）、チートデーの提案（予定より 0.5 kg 以上先に進んでいるとき、ホームでアプリが「この 7 日のうち 2 日まで、維持カロリーまで」を提案。選んだ日はカレンダーに印。決まりは [docs/CHEAT_DAY.md](docs/CHEAT_DAY.md)）。最初の 1 か月は無料で試せて、終わったあとは中身をぼかして「Pro で見られます」と表示（[docs/PRO.md](docs/PRO.md)） | ✅ |
| ホーム画面・ロック画面のウィジェット（最新の体重・目標まで・期限まで・直近 14 日の記録。無料。しくみは [docs/WIDGET.md](docs/WIDGET.md)） | ✅ |
| Pro 機能：キープモード（目標に届いたあと、目標 ±1.5 kg の範囲にキープ。範囲から出そうなとき・出たときにやさしく知らせ、維持カロリーの目安を出す。無料版では目標達成のときに Pro の案内。決まりは [docs/MAINTENANCE_MODE.md](docs/MAINTENANCE_MODE.md)） | ✅ |
| App Store に出す準備（アプリ名「体重予報」、説明文・プレビュー画像の下書き、申請前のチェックリスト。[docs/APP_STORE.md](docs/APP_STORE.md)） | 🚧（下書きまで。プレビュー画像を本物の画面に差し替える・Apple Developer Program の登録などが残り） |
| 課金（買い切りの Pro。値段と投げ銭はまだ決めていない）・英語版（年額サブスクは保留） | ⬜ |
| Apple Watch 対応（Watch から体重を記録、目標まで・期限まで・連続記録、文字盤のコンプリケーション。無料。しくみは [docs/WATCH.md](docs/WATCH.md)） | 🚧（作った。Mac での署名と動作確認がまだ） |

データはすべて端末内（SwiftData）に保存し、外部のサーバーには送りません。

開発の順番は [docs/ROADMAP.md](docs/ROADMAP.md)、目標体重と BMI の考え方は [docs/BMI_GOAL.md](docs/BMI_GOAL.md)、App Store に載せる文章と画像は [docs/APP_STORE.md](docs/APP_STORE.md) を参照してください。

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
│   │   ├── Components/           ← 共通の見た目の部品（カード・大きな数字・注意の一文など）
│   │   ├── Home/                 ← ホームタブ（グラフ・予測・カロリーなどのカード）
│   │   ├── Pro/                  ← Pro の案内画面と、お試し後のぼかした表示
│   │   ├── Maintenance/          ← キープモードのカードと設定
│   │   └── Debug/                ← Debug ビルドだけのデモデータ読み込み
│   ├── Logic/                    ← 計算ロジック（予測・カロリー計算など。画面に依存しない）
│   │   ├── Food/                 ← 食品表の読み込み、食べ物ヒント
│   │   ├── Messages/             ← ほめるメッセージ、連続記録日数
│   │   ├── Calendar/             ← カレンダーのマス目、スタンプの集計
│   │   ├── Health/               ← ヘルスケア連携のルール（重複防止、運動した日の判定、活動量の目安）
│   │   ├── History/              ← 履歴の月ごとの見出し、増減の色、入力の −/＋
│   │   ├── Reminders/            ← 記録のリマインド・ほめる通知の予定と文面
│   │   ├── Pro/                  ← Pro 機能の計算（幅付きの予測、チートデーの提案、Pro を使えるかの判断）
│   │   ├── Maintenance/          ← キープモードの計算（キープの範囲・状態）
│   │   ├── Widget/               ← ウィジェットに出す数字のまとめ
│   │   ├── Watch/                ← Apple Watch から届いた記録を足すかの判断
│   │   └── Demo/                 ← 動作確認用のデモデータ
│   ├── Services/                 ← 外部の仕組み（HealthKit・通知・Apple Watch）とのやり取り
│   ├── Resources/                ← アプリに同梱するデータ（FoodCalories.json：食品のカロリー表）
│   ├── Localizable.xcstrings     ← 画面の文言の一覧（String Catalog）
│   └── Assets.xcassets           ← アイコン・色・画像
├── Shared/                       ← アプリ・ウィジェット・Watch のすべてに入るファイル（ウィジェットと Watch に渡す数字の形・保存・日付の計算）
├── WeightForecastWidget/         ← ホーム画面・ロック画面のウィジェット（拡張のターゲット）
├── WeightForecastWatch/          ← Apple Watch アプリ
├── WeightForecastWatchWidget/    ← Apple Watch の文字盤のコンプリケーション（拡張のターゲット）
├── WeightControlAppTests/        ← 単体テスト（Swift Testing）
├── WeightControlAppUITests/      ← UI テスト（XCTest）
└── .github/workflows/ci.yml      ← GitHub 上で自動ビルド＆テストする設定
```

このプロジェクトは Xcode の「フォルダ同期」方式を使っているので、`WeightControlApp/` の下にファイルやフォルダを追加すると、Xcode のプロジェクトにも自動で反映されます（`Shared/` はアプリ・ウィジェット・Watch アプリ・コンプリケーションのすべて、`WeightForecastWidget/` はウィジェット、`WeightForecastWatch/` は Watch アプリ、`WeightForecastWatchWidget/` はコンプリケーションだけに入ります）。

## はじめかた

1. このリポジトリを Mac に持ってくる（Xcode の **Integrate → Clone…**、または `git clone https://github.com/YutaKanemaru/WeightControl.git`）
2. `WeightControlApp.xcodeproj` をダブルクリックして Xcode で開く
3. 上部のデバイス選択でシミュレーター（例: iPhone）を選び、`⌘R` で実行
4. `⌘U` でテストを実行

## 主なデータ（Models/）

| 型 | 保存するもの |
|---|---|
| `WeightEntry` | 体重（kg）と記録日時。ヘルスケアと同期した記録は、ヘルスケア側の ID と「取り込んだ記録か」も持つ |
| `UserProfile` | 身長（cm）、生まれた年、性別、活動量、消費カロリーの計算方法（自動・活動量・ヘルスケアの実績） |
| `WeightGoal` | 目標体重（kg）、期限、開始日、開始時の体重、期限の決め方（ゆるやか・ハード・自分で決める）、キープモードを始めた日と範囲の幅 |
| `ExerciseDay` | 運動した日（カレンダーの運動スタンプ）。手動か HealthKit からか、運動した分数（HealthKit 用） |
| `CheatDay` | チートデー（Pro）に決めた日 |

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
