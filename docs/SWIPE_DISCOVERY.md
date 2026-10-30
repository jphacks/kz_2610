# お店スワイプ（SwipeDiscovery）

友達がレビューした近くのお店をカードで1枚ずつ見て、右スワイプで「行きたい」、左スワイプで「イマイチ」に振り分ける機能です。
要件は「メシノワ スワイプ機能 要件定義書」（v6）に従い、コードはすべて `meshinowa/Features/SwipeDiscovery/` に置いています。

## 入口と既存コードとの接点

- 入口：友達タブの「フィード」に `SwipeDiscoveryEntry.feedBanner()` を置き、フィードはお店スワイプ専用（友達の記録のタイムラインは削除）。全画面で開きます。
- 地図のお店カード：住所の下に小さな「行きたい」ボタン（`SwipeDiscoveryEntry.wantToGoButton(item:)`）。右スワイプと同じ一覧に入ります。
- 呼び名：要件定義書の「気になる」は、画面上はすべて「行きたい」に統一（アイコンは旗。ハートは既存の「いいね」）。
- ジャンルの#タグ：地図のピンと同じ `FoodGenre` の判定（Google の種類・店名・地図のカテゴリ）で大分類を決め、名前も地図とそろえる（#麺、#寿司 など）。
- 保存画面：`SavedCollection` に `.wantToGo` を追加し、上部の「いいね／行きたい」の切り替えで `SwipeDiscoveryEntry.wantToGoStore` の一覧を出します（`PersonalLibrary`・`SavedLibraryView` を変更）。
- 機能フラグ：`SwipeDiscoveryFeature.isEnabled` を `false` にすると入口ごと消えます。
- 既存の型を参照するのは `Bridges/` だけです（友達データ、レビュー、Google Maps / Places、Cloudflare）。

## 要件定義書からの変更点（確認済み）

| 項目 | 要件定義書 | 実装 |
| --- | --- | --- |
| 「行きたい」 | 既存の「行きたい」に保存 | 既存では「行きたい」が「いいね」に統合されているため、いいねとは別の「行きたい」を新設。端末の `Application Support/SwipeDiscovery/want_to_go.json` に保存し、Cloudflare の `want_to_go` テーブル（`/v1/want-to-go`）と同期。レビューを書くと外れる |
| 「行きたい」の表示場所 | 既存の保存画面 | 保存画面の上部の「いいね／行きたい」の切り替えで表示（長押しで「行きたいから外す」）。お店スワイプの結果一覧にも「行きたい」タブあり |
| 入口 | マップ画面右上 | 友達タブのフィード（マップ画面はナビゲーションバーを隠しているため） |
| 地図・経路 | MKMapSnapshotter・Appleマップ | 既存方針に合わせ Google Maps（小窓は最前面カードだけ実際の地図）。お店スワイプの中には経路のボタンを置かない（経路は既存のお店の詳細から） |
| 写真 | 友達の写真、なければ星評価 | 友達の写真 → なければ Google Places の店舗写真（クレジット付き） → なければ星評価ビュー。友達のレビュー写真はサーバーに共有されない作りのため、今は店舗写真か星評価（共有は別のPRで検討） |
| データ | Friend Lens のデモ | 友達タブと同じく、サーバーから取得した友達の実データだけを使う（main でアプリのデモデータが削除されたため）。未接続・友達なしの時は「近くに友達のレビューがありません」 |
| 現在地 | 既存の「使用中のみ」許可 | アプリの位置情報（LocationStore）で現在地が分かっていれば使い、なければ東京駅周辺。既定エリアの時は「現在地で探す」を出し、押した時だけ許可を求める（地図と同じ方針） |

## 保存するもの

- 判断記録：`Application Support/SwipeDiscovery/swipe_decisions.json`。壊れたら `.broken` に退避。
- 行きたい：`Application Support/SwipeDiscovery/want_to_go.json`。通信できない時は端末に残し、次に開いた時に送ります。
- ガイドの状態：UserDefaults の `swipeDiscovery.` で始まるキー。

## 確認のしかた

- iOS：Xcode で meshinowa スキームを選び Product → Test（⌘U）。`Tests/SwipeDiscovery/` に単体テストがあります。
- Cloudflare：`npm test --prefix cloudflare`（行きたい API のテストを含む）。
- 本番の Cloudflare は今回は用意しません。サーバーにつないだ動きは、下のローカルのダミーデータで確認します。
  本番を用意する時は、`0005_want_to_go.sql` の適用（`npx wrangler d1 migrations apply DB --remote --config wrangler.production.jsonc`）と Worker の更新が必要です。

### ローカルのダミーデータで確認する

ローカルの D1 に、架空の友達5人・お店8軒（うち1軒は半径1kmの外）・レビュー11件を入れます（`cloudflare/scripts/seed-local.mjs`）。
すべてリポジトリのルートで実行します。

```sh
npm ci --prefix cloudflare
npm run db:local --prefix cloudflare
npm run seed:local --prefix cloudflare                       # 東京駅の周り（アプリの既定エリア）
# npm run seed:local --prefix cloudflare -- --near 緯度,経度  # 現在地で試す時は、その地点の周りに置く
npm run dev --prefix cloudflare                              # http://127.0.0.1:8787（動かしたままにする）
```

1. `Config/Cloudflare.xcconfig.local` に接続先を書きます（Git対象外）。
   - シミュレータ：`CLOUDFLARE_API_URL = http:/$()/127.0.0.1:8787`
   - 同じWi-Fiの実機：`cloudflare/README.md` の「同じWi-Fiの実機から接続する開発ビルド」の手順（`dev-device-proxy.py` と `.local` の設定）
2. アプリを起動し（ゲストが作られる）、友達タブの「つながり」に出る自分のIDで、ダミーの友達とつなぎます。
   `npm run seed:local --prefix cloudflare -- --friend <自分のID>`
3. 友達タブを下に引いて更新し、フィード →「お店スワイプ」を開くと【テスト】のお店が出ます。

`--near` を変える時や、やり直したい時は `cloudflare/.wrangler` を消してから 1 からやり直してください。

### 確認すること

- 初回ガイド（灰色とピンクの矢印、お手本の動き）が出て、1枚判断すると消える
- 写真を軽くタップするとカードが飛ばずに写真（または詳細・地図）が開く
- 右スワイプで「行きたいに保存しました」と出て、保存画面の「行きたい」に入る。「戻す」で外れる
- 地図のお店カードの「行きたい」ボタンでも同じ一覧に入る
- `GET /v1/want-to-go` にも入っている（同期）。別のシミュレータで同じアカウントに引き継ぐと同じ一覧になる
- そのお店のレビューを書くと「行きたい」から外れる
- イマイチにしたお店は24時間出ない。「イマイチをリセット」ですぐ戻る
- 「範囲を変える」でスライダーが出て、半径を広げると1kmの外の【テスト】遠くの定食屋が出る
- 「現在地で探す」で位置情報の許可を求め、許可すると現在地の周りで探す
- #タグが地図のピンと同じジャンル名（#麺 など）で出る
