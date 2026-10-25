# お店スワイプ（SwipeDiscovery）

友達がレビューした近くのお店をカードで1枚ずつ見て、右スワイプで「行きたい」、左スワイプで「イマイチ」に振り分ける機能です。
要件は「メシノワ スワイプ機能 要件定義書」（v6）に従い、コードはすべて `meshinowa/Features/SwipeDiscovery/` に置いています。

## 入口と既存コードとの接点

- 入口：友達タブの「フィード」に `SwipeDiscoveryEntry.feedBanner()` を置き、フィードはお店スワイプ専用（友達の記録のタイムラインは削除）。全画面で開きます。
- 地図のお店カード：住所の下に小さな「行きたい」ボタン（`SwipeDiscoveryEntry.wantToGoButton(item:)`）。右スワイプと同じ一覧に入ります。
- 呼び名：要件定義書の「気になる」は、画面上はすべて「行きたい」に統一（アイコンは旗。ハートは既存の「いいね」）。
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
| 写真 | 友達の写真、なければ星評価 | 友達の写真 → なければ Google Places の店舗写真（クレジット付き） → なければ星評価ビュー |
| データ | Friend Lens のデモ | 友達タブと同じく、サーバーから取得した友達の実データだけを使う（main でアプリのデモデータが削除されたため）。未接続・友達なしの時は「近くに友達のレビューがありません」 |
| 現在地 | 既存の「使用中のみ」許可 | アプリの位置情報の許可（LocationStore）がある時は現在地、ない時は東京駅周辺（既定エリア） |

## 保存するもの

- 判断記録：`Application Support/SwipeDiscovery/swipe_decisions.json`。壊れたら `.broken` に退避。
- 行きたい：`Application Support/SwipeDiscovery/want_to_go.json`。通信できない時は端末に残し、次に開いた時に送ります。
- ガイドの状態：UserDefaults の `swipeDiscovery.` で始まるキー。

## 確認のしかた

- iOS：Xcode で meshinowa スキームを選び Product → Test（⌘U）。`Tests/SwipeDiscovery/` に単体テストがあります。
- Cloudflare：`npm test --prefix cloudflare`（行きたい API のテストを含む）。本番 D1 には `npx wrangler d1 migrations apply DB --remote --config wrangler.production.jsonc` で `0005_want_to_go.sql` を適用してください。
- 実機：初回ガイド（灰色とピンクの矢印、お手本の動き）、写真の軽いタップでカードが飛ばないこと、右スワイプで「行きたい」に入り「戻す」で消えること、イマイチが24時間で戻ること。
