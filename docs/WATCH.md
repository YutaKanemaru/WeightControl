# Apple Watch 対応（フェーズ 10）

手首から **すぐ体重を記録できて**、**目標まであと何 kg か・期限まであと何日か** をひと目で見られるようにします。文字盤には **コンプリケーション**（文字盤の小さな表示欄）も置けます。

この文書は作る前の仕様です。作るときに変わったら、この文書も同じ PR で直します。

## 最初の版でできること

| 画面 | 出すもの |
|---|---|
| Watch アプリ（1 画面） | 最新の体重（大きく）・「目標まで ○ kg」（届いたら「達成」）・「期限まで ○ 日」・連続記録日数・「記録する」ボタン |
| 記録の画面 | 前回の体重から始まる大きな数字。**Digital Crown**（Watch の横の回るつまみ）を回すと 0.1 kg ずつ変わる。「記録する」で保存 |
| コンプリケーション | 下の「コンプリケーションの種類」の 4 種類から、文字盤の好きな場所に好きなものを置ける |

- 出す数字は **ホームとウィジェットと同じ値** です（「目標まで」は最新の体重から `GoalDistanceCalculator` で出す。[WEIGHT_RECORDS.md](WEIGHT_RECORDS.md)）。Watch では計算せず、iPhone が作った数字を表示するだけにします。
- キープモード（Pro）中は、ウィジェットと同じく「目標まで」のかわりに「キープ 62.5〜65.5 kg」を出し、期限は出しません。
- 前回と **2.0 kg 以上** ちがう体重を記録しようとしたら、iPhone の入力画面と同じく「前回と 2.3 kg ちがいます。このまま記録しますか？」と確かめます。
- 記録したら「記録しました」と軽い手ごたえ（触覚）を返し、ほめる一言（「今日も記録できました」）を出します。責める言い方はしません。
- **無料** です（ウィジェットと同じ考え方。記録と今の状態を見るのは無料。[PRO.md](PRO.md)）。

### コンプリケーションの種類

文字盤には、隅（角）・丸い枠・1 行・長方形などの置き場所があります。**出す中身ごとに別のコンプリケーション** にしておくので、文字盤の編集画面で「左上の隅に 目標まで、右上に 期限まで、下に 連続記録」のように、場所ごとに選んで組み合わせられます。

| 種類 | 隅（角） | 丸 | 1 行 | 長方形 |
|---|---|---|---|---|
| 目標まで | 「3.2」＋弧で進み具合 | 進み具合の輪＋「3.2」 | 「目標まで 3.2 kg」 | — |
| 期限まで | 「45日」 | カレンダーのアイコン＋「45」 | 「期限まで 45 日」 | — |
| 連続記録 | 「12日」 | ✓ のアイコン＋「12」 | 「連続 12 日」 | — |
| まとめ | — | — | — | 体重・目標まで・期限まで・連続記録を 1 枚に |

- 届いたら「目標まで」は「達成」、キープモード（Pro）中は「キープ中」と範囲の内外を出します。
- 期限を過ぎたら「期限まで」は「期限すぎ」、今日なら「今日」。
- 連続記録は、昨日までに記録が途切れていたら 0 日（ウィジェットと同じ `WidgetDisplay.visibleStreakDays`）。
- 日付が変わると「期限まで」「連続記録」が変わるので、毎日 0 時に描き直します（ウィジェットと同じ）。
- どれも押すと Watch アプリが開きます。

### 最初の版ではやらないこと

- Watch での記録の修正・削除（iPhone の履歴で行う）。
- グラフ、予測（目標に届く日）、カロリーの目安、チートデー。Watch の画面は小さいので、まずは「記録」と「あと何 kg・何日」にしぼります。
- iPhone なしで Watch だけで使うこと（記録は iPhone に届いてから正式に保存されます。下の「データの受け渡し」）。

## データの受け渡し：WatchConnectivity を使う

Watch と iPhone は別々の機械なので、データを受け渡すしくみが必要です。候補は 3 つありました。

| やり方 | よいところ | 困るところ |
|---|---|---|
| **WatchConnectivity**（Apple 純正の「iPhone と Watch でメッセージをやりとりする」しくみ）← **これを使う** | 近くにあれば 1 秒ほどで届く。離れていても、つながったときに順番に届く。ヘルスケアをオフにしている人も使える | iPhone 側の受け取りのコードが要る |
| ヘルスケア（HealthKit）経由：Watch でヘルスケアに体重を書き、iPhone で取り込む | 受け渡しのコードがいらない | ヘルスケア連携をオンにしている人しか使えない。iPhone に届くまで数分かかることがある。「目標まで」を Watch に返せない |
| SwiftData を iCloud で共有 | 同じデータを両方で使える | データが Apple のサーバー（iCloud）を通る。「データは端末内のみ」の方針に合わない |

WatchConnectivity は、iPhone と Watch のあいだで直接（Bluetooth や Wi-Fi で）やりとりするので、データは外のサーバーを通りません。

### 流れ

```
iPhone アプリ                                Watch アプリ
─────────────                                ────────────
記録・目標が変わる
  → ウィジェット用と同じスナップショットを作る
  → updateApplicationContext で送る  ───▶  受け取って保存 → 画面とコンプリケーションを更新

                                              「記録する」を押す
                                                → 送信待ちの一覧に入れる（画面にはすぐ出す）
受け取る  ◀───  近くにあれば sendMessage、なければ transferUserInfo
  → SwiftData に WeightEntry を足す
  → ヘルスケア連携がオンならヘルスケアにも書く（iPhone の入力と同じ）
  → 新しいスナップショットを送り返す  ───▶  送信待ちから消して、新しい数字を出す
```

使う 3 つの送り方（どれも WatchConnectivity の `WCSession` の機能）：

- **`updateApplicationContext`**（iPhone → Watch）：「いまの状態」を 1 つだけ送る。新しいものを送ると古いものは捨てられるので、スナップショットのように「最新だけあればよい」ものに向いている。
- **`sendMessage`**（Watch → iPhone）：近くにあって、すぐ届くときに使う。iPhone のアプリが閉じていても、iOS が裏で起こしてくれる。
- **`transferUserInfo`**（Watch → iPhone）：届くまで順番に待ってくれる送り方。iPhone が遠くにあるとき・電源が切れているときに使い、つながったら届く。記録が消えないように、`sendMessage` が失敗したときもこちらで送り直す。

### 送るデータの形

- **iPhone → Watch**：ウィジェットと同じ `WidgetSnapshot`（`Shared/` にある）を JSON にしたもの。ウィジェットとまったく同じ数字になります。
- **Watch → iPhone**：`WatchWeightRecord`（新しく `Shared/` に置く）
  - `id`（UUID。同じ記録を 2 回足さないため）
  - `date`（Watch で「記録する」を押した日時）
  - `weightKg`（kg、小数 1 桁）

### 同じ記録を 2 回足さない

`sendMessage` が届いたのに返事だけ失敗した場合などに、同じ記録が `transferUserInfo` でもう一度届くことがあります。iPhone は、受け取った記録の `id` を覚えておき（最近の 200 件。`UserDefaults`）、同じ `id` は足しません。この判断は `Logic/Watch/WatchRecordImportPlanner` に置いてテストします（体重の範囲のチェックも、iPhone の入力と同じルールで行う）。

### Watch に「送信待ち」があるとき

- 送った記録が iPhone に届くまでは、その体重を「最新の体重」として出し、小さく「iPhone に送信待ち」と出します。
- 「目標まで」「期限まで」は、iPhone から新しいスナップショットが届くまで前の値のままです（Watch では計算しないため。近くに iPhone があれば 1 秒ほどで新しい値になります）。
- iPhone から届いたスナップショットの最新の記録が、送信待ちの記録と同じ（またはそれより新しい）なら、送信待ちから消します。

## 画面の見た目

CLAUDE.md の「UI の見た目の方針」と同じです。

- いちばん大事な数字（体重・目標まで）は大きく太く、`monospacedDigit()`。
- アイコンは SF Symbols（体重は `scalemass.fill`、期限は `calendar`）。色はアクセントカラーと、達成＝緑・キープの範囲外＝オレンジだけ。
- アクティビティリング（3 色の輪）のような Apple 独自のデザインはまねしません。進み具合はアクセントカラー 1 色の `Gauge`（SwiftUI 標準の目盛りの部品）で出します。
- 数字には `privacySensitive()` を付けます（ロック中の文字盤では隠れる）。
- 記録がない・目標がない・iPhone とまだつながっていないときは、「iPhone のアプリで記録すると、ここに出ます」のような一言を出します。

## 作るもの（ファイルとターゲット）

ターゲットは「ビルドしてできあがるもの 1 つ分の設定」です。Watch 用に 2 つ足します。

| ターゲット | 何か | バンドル ID | フォルダ |
|---|---|---|---|
| `WeightForecastWatch` | Watch アプリ本体（watchOS 26.0 以上） | `com.utahengineering.weightforecast.watchkitapp` | `WeightForecastWatch/` |
| `WeightForecastWatchWidgetExtension` | コンプリケーション（Watch 用の WidgetKit 拡張） | `com.utahengineering.weightforecast.watchkitapp.widget` | `WeightForecastWatchWidget/` |

- Watch アプリは iPhone アプリの中に入れて配ります（iPhone アプリを入れると、ペアリングした Watch にも入れられる）。App Store でも 1 つのアプリとして出ます。
- `Shared/` は 4 つのターゲット（iPhone アプリ・ウィジェット・Watch アプリ・コンプリケーション）すべてに入れます。ここに `WatchWeightRecord` と、Watch 側の表示のルール（送信待ちの扱い、Digital Crown の 0.1 kg 刻み、2.0 kg の確認）を Foundation だけで置き、テストはアプリ側のテストで書きます。
- コンプリケーションと Watch アプリは、Watch の中の App Group（`group.com.utahengineering.weightforecast`、iPhone と同じ名前でよい。Watch の中だけの共有の引き出しになる）でスナップショットを分け合います。読み書きは `WidgetSnapshotStore` をそのまま使います。
- iPhone 側：
  - `Services/WatchSyncService`：`WCSession` の窓口。スナップショットを送り、届いた記録を SwiftData に足す。
  - スナップショットを作る処理を、画面（`WidgetSnapshotSync`）から呼べるだけでなく、Watch から記録が届いたとき（アプリが裏で起こされたとき）にも呼べる形に整理する。ウィジェットへの保存と Watch への送信を同じ場所で行う。
  - `Logic/Watch/WatchRecordImportPlanner`：重複と範囲のチェック（テストあり）。
- ヘルスケアへの書き込みは iPhone が行うので、Watch アプリはヘルスケアの許可を求めません。

## Mac で Yuta がすること（実装の PR がマージされたあと）

プロジェクトファイルの設定はこちらで書きますが、**署名**（アプリが本物の開発者のものだと証明するしくみ）は Mac の Xcode でしか確かめられません。

1. Xcode でプロジェクトを開き、左の一覧のいちばん上（青いアイコン）を選ぶ。
2. **TARGETS** の `WeightForecastWatch` →「Signing & Capabilities」を開き、Team が自分のチームになっているか確かめる（エラーが出たら「Automatically manage signing」にチェック）。
3. 同じ画面の「App Groups」に `group.com.utahengineering.weightforecast` があってチェックが入っているか確かめる。`WeightForecastWatchWidgetExtension` でも同じことをする。
4. 試すとき：画面上の実行先（▶ の右）で、スキームを `WeightForecastWatch`、実行先を Watch のシミュレーター（iPhone のシミュレーターとペアになっているもの）にして ▶。Watch のシミュレーターがなければ「Xcode → Settings → Components」から watchOS を入れる。
5. 実機で試すとき：iPhone に Watch がペアリングされていれば、iPhone にアプリを入れたあと、iPhone の「Watch」アプリ →「マイウォッチ」→ 下のほうの「体重予報」→「インストール」。

## CI（GitHub Actions）について

Watch アプリを iPhone アプリに入れると、iPhone アプリをビルドするときに Watch アプリもいっしょにビルドされます。CI の Mac に watchOS の部品が入っていないとビルドが失敗するので、実装の PR で CI の設定に「watchOS の部品がなければ入れる」手順を足します。単体テストは今と同じく iPhone のシミュレーターで行います（`Shared/` と `Logic/Watch/` のテストを含む）。

## あとで考えること

- Watch での記録の取り消し（記録した直後の「取り消す」ボタン）。
- Pro の人には「目標に届く日」も出す。
- iPhone なしでも Watch だけで記録を見られるようにする（Watch に記録を保存する）。
- Watch のヘルスケアにも直接体重を書く（いまは iPhone 経由でヘルスケアに入る）。
