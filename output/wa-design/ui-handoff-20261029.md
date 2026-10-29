# Handoff: meshinowa UI 改善（1b・2b・3a・4a・5a）

## 概要
meshinowa（SwiftUI / iOS 17+）の5画面を改善する。採用案は次のとおり。

| 画面 | 採用案 | 方針 | 主な対象ファイル |
|---|---|---|---|
| 地図（上部UI・店舗カード） | 1b | 構成から見直す | `Views/MapHomeView.swift`, `Views/RestaurantPreview.swift`, `DesignSystem/NorenTabs.swift` |
| 保存 | 2b | 構成から見直す | `Views/SavedLibraryView.swift`（`SavedRestaurantsView`） |
| 友達（友達0人） | 3a | 小さく整える | `Views/FriendsHomeView.swift` |
| プロフィール | 4a | 小さく整える | `Views/ProfileView.swift` |
| レビュー編集 | 5a | 小さく整える | `Views/ReviewEditor.swift`, `DesignSystem/RatingInput.swift` |

テーマは「モダン＋和の要素」。

**色合いは全画面を保存画面（2b）に統一する。** 画面の地は `cream`（#FDF8EE）、その上のカード・入力欄・チップ・サブボタンは白（#FFFFFF）＋1pt `hairline`（#E3E5E2）。今 `field`（#F4F5F2）を使っている面は白＋細線に置き換える。地図（1b）は地図が地なので、店舗カード自体を `cream` にし、中のアクションを白＋細線にする。タブバーと地図上の浮いた部品（検索欄・現在地ボタン）は白のまま。

和の要素は 1b・2b に集中している（竿に掛かるのれん、縦書きのジャンル札、判子、クリーム地、Zen Maru Gothic の見出し）。3a・4a・5a は今のトーンのまま整理する。

## デザインファイルについて
このフォルダの HTML は **デザインの見本** であり、そのまま使うコードではない。既存の SwiftUI コードベースの部品・パターン（`MeshinowaTheme`, `MeshinowaFont`, `NorenTabs`, `FoodGenreMark`, `PaperCard`, `PaperButtonStyle` など）を使って再実装すること。

- `Adopted.dc.html` … 採用した5案だけを並べた見本。ブラウザで開くと見られる（`support.js` と同じフォルダに置いたまま開く）。各画面の下に変更点のメモがある。
- `TabBar.dc.html` … タブバー（変更なし。見本の表示用）。
- 寸法は iPhone 393×852pt を基準にした pt 値。

## 再現度
**ハイファイ**。色・文字サイズ・余白は下記の値どおりに実装する。ただしアイコンは見本では Material Symbols を代用しているので、実装では今使っている SF Symbols に置き換える（例: `favorite`→`heart`, `flag`→`flag`, `star`→`star`, `refresh`→`arrow.clockwise`, `replay`→`arrow.uturn.backward`, `add_a_photo`→`camera.badge.plus` 相当, `ios_share`→`square.and.arrow.up`, `content_copy`→`doc.on.doc`, `delete`→`trash`, `lock`→`lock`）。

---

## 共通トークン（すべて既存の `MeshinowaTheme`）
| 用途 | トークン | 値 |
|---|---|---|
| 地 | `paper` / `card` | #FFFFFF |
| 和の地（2bのみ） | `cream` | #FDF8EE |
| 入力欄・面 | `field` | #F4F5F2 |
| 細線 | `hairline` | #E3E5E2 |
| 枠線 | `outline` | #D5D8D4 |
| 写真なしの面 | `photo` | #EADFCB |
| 文字 | `ink` / `bodyText` / `secondaryText` | #1C1F1D / #4F5550 / #6B716D |
| ブランド | `green` / `mint` / `mintInk` | #27755B / #DDF0E4 / #1F6B4F |
| 自分の評価のみ | `accent` / `mustardSoft` / `mustardInk` | #E8AD45 / #FBEBC8 / #7A5410 |
| いいねのみ | `like` / `likeInk` | #E5577E / #A3254B |
| 削除 | （新規）`danger` | #D93A3A ※既存の削除色があればそれを使う |
| のれんの竿（1b・2b） | `mustardInk` を流用 | #7A5410 |

色の決まりは今のまま守る：からし色＝自分の評価、ピンク＝いいね、緑＝ブランド・行きたい・選択中。

### フォント
- 本文: `MeshinowaFont.text(...)`（ヒラギノ角ゴ W3/W6）
- 見出し・数字: `MeshinowaFont.heading/number`（M PLUS Rounded 1c ExtraBold）
- **新規** 和の見出し（1b・2b のみ）: Zen Maru Gothic。`Resources/Fonts/zenmarugothic/` にすでにある。`Info.plist` の `UIAppFonts` に入っているか確認し、`MeshinowaFont` に次を追加する。
  ```swift
  static func wa(_ size: CGFloat, bold: Bool = true, relativeTo style: Font.TextStyle = .headline) -> Font {
      .custom(bold ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Medium", size: size, relativeTo: style)
  }
  ```

### 角丸・影
- カード 16〜22pt（`.continuous`）、ボタン 12pt、チップ・ピル 高さの半分
- 浮いている部品の影: `black 16%, radius 8, y 2`（既存と同じ）
- カードの弱い影: `black 8%, radius 4, y 1`

---

## 1b 地図（上部UI・店舗カード）

### 上部
1. **検索欄**（top 58 / 左右 12 / 高さ 50 / 角丸 25 の完全なピル / 白 / 影）
   - 左に虫めがね（21pt, `green`）、プレースホルダー「お店やジャンルを探す」16pt `#B4B8B5`
   - 右に「すべて／友達」のセグメント（地 `field`、内側 3pt、各 30pt 高・角丸15・12pt W6。選択中は白地＋弱い影＋`mintInk`）
   - **一覧ボタン（件数）は検索欄から外す**（件数は店舗カード内へ移動、下記）
2. **のれん（竿付き）**（検索欄の下 10pt、高さ 50）
   - 竿: 高さ 4pt・角丸 2・色 `mustardInk`、左右 10pt 内側、影 `black 25% r1 y1`
   - のれんは竿の 3pt 下から、左 18pt から並ぶ。間隔 3pt
   - 未選択: 幅 52・高さ 28・白・角丸（上 2 / 下 8）・Zen Maru Medium 13pt
   - 選択中: 幅 60・高さ 40・`green`・裾の中央に切れ目（幅 5 / 深さ 8）・Zen Maru Bold 13pt 白
   - `NorenTabs` を拡張して、`style: .rod`（竿付き・小さめ）を追加するのがよい。短い高さ 28 / 長い高さ 40、固定幅を `fitsCount` 超過時 52pt に。今の落ちて揺れるアニメーションはそのまま使う
   - 右端 14% をフェードアウト（`mask` に横グラデーション）して、横スクロールできると分かるようにする
   - アイコン（grid_view 等）はのれんから外し、文字だけにする

### 中段
- 「このエリアで探す」: 地図を動かしたときだけ出す。**緑の塗りをやめ** 白地・`green` 文字・14pt W6・高さ 36・ピル。左に再読み込みアイコン。店舗カードの上 14pt、横中央
- 現在地ボタン: 44pt 円・白、同じ行の右端（right 14）

### 店舗カード（`RestaurantPreview`）
- 位置: 左右 12 / タブバーの上 / 角丸 22 / 内側 10 / **`cream` 地** / 影 `black 18% r14 y4`
- 横スワイプで前後のお店に移る挙動は今のまま
- **写真**: 幅いっぱい・高さ 128・角丸 14
  - 左上（left 12, top 0）に **ジャンルの縦書き札**: `green` 地、白、Zen Maru Bold 14pt、字間 3、内側 上10/左右6/下12、下だけ角丸 6、影 `black 20% r4 y2`。縦書きは `VStack` で1文字ずつ並べる
  - 右上に **件数**「1 / 20」: 高さ 24・ピル・`ink` 55% 地・白・M PLUS 12pt（「/ 20」は 70% 不透明）。**タップで一覧シートを開く**（今の一覧ボタンの代わり）
  - 右下に写真の出典「写真：○○」10pt 白、文字の影
  - 写真がないときは `photo` 地に `FoodGenreMark` を中央に置く
- **店名**: Zen Maru Bold 21pt、行間 1.3、**2行まで**（今は1行で切れる）
- **住所**: 13pt `bodyText`、左にピンアイコン 15pt `secondaryText`、1行で省略
- **アクション3つ**（店名の下 12pt、3等分グリッド、間隔 8）
  - 各: 高さ 56・角丸 14・白＋1pt `hairline`・アイコン 22pt の下にラベル 12pt W6
  - 「評価する」星 `accent` / 「いいね」ハート `like` / 「行きたい」旗 `green`
  - オンの状態: アイコンを塗りに、地をそれぞれ `mustardSoft` / `likeSoft` / `mint` にする
- カテゴリが「飲食店」になる問題: Places の種類からジャンルを決められない場合は札を出さない（「飲食店」とは出さない）

## 2b 保存

- 画面の地を `cream`（#FDF8EE）に変える（この配色を全画面の基準にする）
- **見出し**「保存」Zen Maru Bold 28pt、左右 20
- 右上にアイコンボタン2つ（44pt 円・白・弱い影・間隔 8）: 検索 / 地図表示。**検索欄と地図ボタン（文字付き）は外す**。検索はタップで検索バーを上に出す（`.searchable` で可）
- **いいね／行きたいの切り替え**: 地図と同じ竿＋のれん（見出しの下 14pt）
  - 竿: 左右 −6 まではみ出す、高さ 4、`mustardInk`
  - のれん2枚を2等分（間隔 4）。選択中は高さ 46・`green`・切れ目付き・白文字。未選択は高さ 34・白・角丸 下 9
  - 中身: アイコン（いいね＝ハート、行きたい＝旗 `green`）＋ Zen Maru 15pt ＋件数 M PLUS 14pt
  - 今の下線タブを置き換える
- **並び替え・絞り込み**: のれんの下 12pt、左寄せのチップ（高さ 32・ピル・白・1pt `hairline` 枠・13pt）
  - 「保存した順 ▾」（メニュー）、「未レビューだけ」（トグル。オンは `green` 枠 2pt・`mint` 地）
  - 今の太枠の並び替えボタンをやめる
- **一覧を2列のカードに**（左右 20・間隔 12）※新しいレイアウト
  - カード: 白・角丸 16・影 `black 8% r4 y1`
  - 写真 高さ 124（なければ `photo` 地＋ `FoodGenreMark` 54pt）
  - 左上にジャンルの縦書き札（1bと同じ形、12pt・字間 2・内側 8/4/10・下角丸 5）
  - 右上にいいねの印（26pt 円・`like`・白 2pt 枠・白ハート 14pt）。いいねタブでは常に出る
  - 自分の評価があれば写真の右下に **判子**（46pt 角・角丸 9・枠 3pt `accent`・地 #FFFDF5・−6°回転・点数 M PLUS 16pt＋「自分」Zen Maru Bold 8pt 字間 2・色 `mustardInk`）
  - 写真の下: 店名 Zen Maru Bold 15pt 行間 1.35（2行まで）、エリア（「丸の内2丁目」）11pt `secondaryText`
- 一番下の「0件を表示中」の文は削除
- スワイプで外す操作は、2列ではやりにくいので長押しのコンテキストメニューに「保存から外す」を置く

## 3a 友達（友達0人の状態）

今の見出し・「追加」ボタン・3つのタブはそのまま。タブの下の中身だけ変える。
- 上の緑の帯「友達の『うまい』を地図に集めよう／友達0人・0軒の評価」と、「まずは友達とつながろう」のカードを**削除**し、次に置き換える
- **空の状態**（上 40pt、中央そろえ、間隔 12）
  - 84pt の `mint` 円にロゴ 52pt
  - 見出し「まずは友達とつながろう」M PLUS 20pt
  - 説明「友達がつけた評価が、地図のピンと／このページのおすすめに集まります。」14pt `bodyText` 行間 1.6
- 画面の地は `cream`。ロゴの円は `mint` ではなく白＋弱い影。選択中タブの下線は `green`
- **自分のID**（説明の下 24pt、左右 20）: 白＋1pt `hairline`・角丸 14・内側 14/16
  - 左: 「あなたのID」12pt W6 `bodyText` ／ ID を M PLUS 22pt 字間 0.5
  - 右: 「コピー」ボタン（高さ 36・ピル・白・1pt `outline`・13pt W6・アイコン付き）。押したら「コピーしました」を短く出す
- **ボタン2つ**（IDの下 12pt、縦並び・間隔 10）
  - 主: 「IDを送って友達を招く」高さ 50・角丸 12・`green`・白・M PLUS 16pt → `ShareLink`
  - 副: 「友達のIDで探す」高さ 50・白・1pt `outline` → 今の「追加」シートのID検索を開く
- 友達が1人以上になったら今の表示に戻す

## 4a プロフィール

- 見出し「プロフィール」と設定ボタンはそのまま
- **プロフィールのカードをやめて1行に**（見出しの下 20pt）
  - ロゴ入り `mint` 円 64pt ／ 名前 M PLUS 22pt ＋「この端末のプロフィール」13pt `secondaryText` ／ 右に「編集」ボタン（高さ 36・ピル・1pt `outline`・13pt W6・鉛筆アイコン）
  - 今の幅いっぱいの「プロフィールを編集」ボタンは削除
- 画面の地は `cream`。ロゴの円は白＋弱い影、「編集」ボタンは白＋`hairline`
- **件数**（行った・いいね・友達）: カードの影をやめ、白＋1pt `hairline`・角丸 16・内側 上下 14。数字 M PLUS 24pt、ラベル 12pt `bodyText`、区切り線 1×36 `hairline`
- **よく行くジャンル**
  - 見出しの右に「1 / 9 ジャンル」13pt `secondaryText`（行ったジャンル数 / 全9）
  - **横スクロールをやめ、5列のグリッド**（2段、行間 12）。9つ全部が見える
  - 各: `FoodGenreMark` 36pt の下にラベル 11pt。行ったジャンルは「和食 1」のように件数を W6 で添え、`ink`。0件は不透明度 40%、ラベル `secondaryText`
- **最近のレビュー**: ジャンルの下にすぐ置く（最初の画面で1件目が見えるように）
  - 見出しの右に「すべて見る」13pt W6 `green` → 今の「自分のレビュー一覧」へ
  - 行: 46pt 角丸 11 のサムネ（なければ `photo` 地＋器） ／ 店名 M PLUS 16pt ＋ 日付 12pt ／ 右に今の自分の評価タグ（`mustardSoft` 地・「自分」11pt＋点数 M PLUS 15pt）
- メニュー行は「マイマップ」だけ残す（「自分のレビュー一覧」は「すべて見る」に統合）
- 一番下の保存場所の説明文は設定画面へ移す（タブバーと重なっていたため）

## 5a レビュー編集

- シート・「キャンセル」・タイトル「レビューを編集」はそのまま
- **削除をナビゲーションバーの右へ**: 44pt 円・白・影・ゴミ箱アイコン 22pt `danger`。押すと今の確認ダイアログを出す。一番下の「レビューを削除」は外す（新規作成時はボタン自体を出さない）
- **店の行**: サブ行を「和食・丸の内２丁目 KITTE 6F」（ジャンル・短い住所）に。ジャンルが分からないときは住所だけ（「飲食店」は出さない）
- **評価**: 星と点数を1つの帯にまとめる
  - `mustardSoft` 地・角丸 16・内側 14/16・左右に並べる
  - 左: 星5つ 40pt（間隔 2）。操作は今の `RatingInput` のまま（同じ星をもう一度押すと0.5下がる）
  - 右: 点数 M PLUS 30pt ＋「あなたの評価」11pt W6、色 `mustardInk`、右寄せ
  - 「どうだった？」の見出しは外す。「同じ星をもう一度押すと0.5下がります」は **初回だけ** 帯の下に出す（`@AppStorage` で表示済みを記録）
- **トグル2つ**（帯の下 16pt、横並び・間隔 8・高さ 40・ピル）
  - 「また行きたい」: **アイコンをハートから `arrow.uturn.backward`（もう一度）に変更**（ハートはいいね専用のため）。オン: `mint` 地・`green` 2pt 枠・`mintInk` W6。オフ: 1pt `outline`
  - 「来店日」（記録済みなら「10月26日」のように日付を表示）
- シートとボタンの下の帯の地は `cream`。店のサムネ（写真なし）は白＋`hairline`
- **入力を1枚のカードにまとめる**: 白・1pt `hairline`・角丸 14。中を細線（左右 12 内側）で3段に区切る
  1. ひとこと: ラベル 12pt W6 ＋ 右に「0 / 300」、入力欄（最小高さ 60）、プレースホルダー「どこがよかった？　友達に伝えるつもりで」
  2. おすすめ料理: 1行。左にラベル（幅 72）、右に入力、プレースホルダー「デミグラスのオムライス」
  3. 写真: 64pt 角丸 12 の追加ボタン（`cream` 地・1.5pt 破線 `green`・`green` のカメラアイコン＋「写真」10pt W6）＋説明「5枚まで・位置情報は消して保存」12pt `secondaryText`。追加後はサムネを横に並べる
- 端末保存の注意は1行に短く: 鍵アイコン＋「この端末だけに保存されます」12pt `secondaryText`
- 下の「更新する」ボタンは今のまま（新規作成時は今の文言）

---

---

## 全画面への配色の適用（採用5画面以外も含む）
採用5画面だけでなく、アプリの**すべての画面**を保存画面（2b）の配色にそろえる。テーマを1か所変えて、画面の地として使っている箇所だけを差し替える。

### 1. `MeshinowaTheme` に面のトークンを追加
```swift
// 面
static let ground = hex(0xFDF8EE)   // 新規: 画面の地（クリーム）
static let paper = Color.white      // 変えない（緑の上の白文字・ロゴの穴などにも使っているため）
static let card = Color.white
static let field = hex(0xF4F5F2)    // 新規の箇所では使わない（下記）
```
`paper` の値をそのまま cream に変えると、バッジの白文字（`MainTabView` 130・134行）やロゴの穴（`PaperCard` 159行 `BowlMark.holes`）まで色が変わるので、**値は変えずに使う場所を差し替える**。

### 2. 画面の地を `ground` に（`.background(MeshinowaTheme.paper)` → `ground`）
| ファイル | 箇所 |
|---|---|
| `Views/WelcomeView.swift` | 52, 55行 |
| `Views/MapHomeView.swift` | 地図の外側の地がある場合 |
| `Views/SavedLibraryView.swift` | 167行 |
| `Views/FriendsHomeView.swift` | 65, 377（友達のプロフィール）, 509（友達を追加）行 |
| `Views/FriendRecommendationsView.swift` | 132行（上の帯）。206行の下のシートは `ground` |
| `Views/FriendLensPicker.swift` | 67, 75行 |
| `Views/ProfileView.swift` | 109, 235（プロフィール編集）, 288（自分のレビュー）, 366（マイマップ）行 |
| `Views/AccountSettingsView.swift` | 45行 |
| `Views/SearchResultsView.swift` | 55行 |
| `Views/RestaurantPreview.swift` | 177, 301, 311行（シートの地）。62行の店舗カードも `ground`（1b） |
| `Views/ReviewEditor.swift` | 106, 118, 162行 |
| `Features/SwipeDiscovery/Views/SwipeTheme.swift` | 9行 `background` を `dynamic(light: 0xFDF8EE, dark: 0x171A18)` に。11行 `field` を使う箇所は `card`＋`hairline` に（お店スワイプは独自テーマなのでここだけ変えれば画面全体に効く） |

`presentationBackground` を使うシートもすべて `ground` にする。`Form`/`List` を使う画面（設定・プロフィール編集など）は `.scrollContentBackground(.hidden)` を残したまま地を `ground` にし、セルの地は `.listRowBackground(MeshinowaTheme.card)` で白にする。

### 3. `field`（灰色の面）を白＋細線に

`SwipeTheme` には Dark 用の値があるので、`MeshinowaTheme.ground` も Dark 対応が要るなら同じ `dynamic(light:dark:)` の形で定義する。
cream の上では灰色の面が濁って見えるため、`field` の塗りはやめて **白＋1pt `hairline`** にする。
| ファイル | 箇所 |
|---|---|
| `Views/FriendsHomeView.swift` | 40, 574, 637行 |
| `Views/SavedLibraryView.swift` | 209行（検索欄。2bでは検索はアイコン化） |
| `Views/ReviewEditor.swift` | 214行（すでに `hairline` の枠あり → 塗りを `card` に） |
| `DesignSystem/PaperCard.swift` | 56行 `.neutral` → `card`（枠を `hairline` で付ける） |
| `DesignSystem/NorenTabs.swift` | 342行（プレビュー用。`ground` に） |

例外: 地図の上に浮かぶ白い部品（検索欄・その中のセグメント `MapHomeView` 306行・現在地ボタン）と、タブバーは今の白／灰色のまま。地図の上では白が一番見やすいため。

### 4. 変えないもの
- `card`（白）はカード・チップ・ボタンの地としてそのまま使う（2bと同じ）
- `mint` / `mustardSoft` / `likeSoft` などの色付きの面はそのまま
- 写真なしの面 `photo`（#EADFCB）はそのまま。ただし小さいサムネ（46〜64pt）は白＋細線にする（4a・5a）
- 文字色・ブランド色・評価やいいねの色の決まりは変えない

### 5. 確認
- Light モードのみ確認でよい（今のアプリも Light 固定なら）。Dark 対応がある場合は `ground` に Dark 用の値が必要
- 白い部品が cream の上で埋もれないか、影または `hairline` があるか全画面で確認する

## 状態・ロジックの追加
- 1b: 店舗カードの件数タップ → 既存の一覧シートを開く。「このエリアで探す」は地図が動いたあとだけ表示（今の条件のまま）
- 2b: `layout` を2列グリッドに。「未レビューだけ」トグル、並び順メニュー、検索表示フラグ
- 3a: `friends.isEmpty` のとき空の状態を出す。IDコピー後のトースト
- 4a: 行ったジャンル数（`genreCounts.filter { $0 > 0 }.count`）
- 5a: 0.5操作の説明を出したかどうか（`@AppStorage("didShowHalfStarHint")`）

## アセット
- `assets/map-bg.png`, `assets/shop-photo.png` … 見本用にアプリのスクリーンショットから切り出したもの。実装では使わない
- `fonts/` … アプリに同梱済みのフォントのコピー（見本の表示用）
- 器のマーク・ロゴは見本では既存の `FoodGenreMark` / ロゴの形を SVG で写したもの。実装では既存のビューを使う

## ファイル
- `Adopted.dc.html` … 採用案5画面の見本（メインの参照）
- `TabBar.dc.html` … 見本で使うタブバー
- `support.js` … 見本を開くための実行ファイル（実装には不要）
