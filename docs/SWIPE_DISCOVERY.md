# お店スワイプ（SwipeDiscovery）

友達がレビューした近くのお店をカードで1枚ずつ見て、右スワイプで「気になる」、左スワイプで「イマイチ」に振り分ける機能です。
要件は「メシノワ スワイプ機能 要件定義書」（v6）に従い、コードはすべて `meshinowa/Features/SwipeDiscovery/` に置いています。

## 入口と既存コードとの接点

- 入口：友達タブの「フィード」の先頭に `SwipeDiscoveryEntry.feedBanner()` を1行追加（既存ファイルの変更はこの1か所）。全画面で開きます。
- 機能フラグ：`SwipeDiscoveryFeature.isEnabled` を `false` にすると入口ごと消えます。
- 既存の型を参照するのは `Bridges/` だけです（友達データ、レビュー、Google Maps / Places、Cloudflare）。

## 要件定義書からの変更点（確認済み）

| 項目 | 要件定義書 | 実装 |
| --- | --- | --- |
| 「行きたい」 | 既存の「行きたい」に保存 | 既存では「行きたい」が「いいね」に統合されているため、いいねとは別の「行きたい」を新設。端末の `Application Support/SwipeDiscovery/want_to_go.json` に保存し、Cloudflare の `want_to_go` テーブル（`/v1/want-to-go`）と同期。レビューを書くと外れる |
| 「行きたい」の表示場所 | 既存の保存画面 | 今回はお店スワイプの結果一覧の「行きたい」タブ。既存の保存画面への表示は後で対応（`SwipeWantToGoStore.shared` を使えます） |
| 入口 | マップ画面右上 | 友達タブのフィード（マップ画面はナビゲーションバーを隠しているため） |
| 地図・経路 | MKMapSnapshotter・Appleマップ | 既存方針に合わせ Google Maps（小窓は最前面カードだけ実際の地図）、経路は Google Maps の徒歩経路 |
| 写真 | 友達の写真、なければ星評価 | 友達の写真 → なければ Google Places の店舗写真（クレジット付き） → なければ星評価ビュー。デモの架空店舗では店舗写真を探さない |
| データ | Friend Lens のデモ | サーバー接続時は友達の実データ、未接続はデモ（友達タブと同じ）。デモの店は「行きたい」に入れず、判断記録も別ファイル |
| 現在地 | 既存の「使用中のみ」許可 | アプリに位置情報の許可がないため、許可済みの時だけ使い、通常は東京駅周辺（既定エリア）で探す |

## 保存するもの

- 判断記録：`Application Support/SwipeDiscovery/swipe_decisions.json`（デモは `swipe_decisions_demo.json`）。壊れたら `.broken` に退避。
- 行きたい：`Application Support/SwipeDiscovery/want_to_go.json`。通信できない時は端末に残し、次に開いた時に送ります。
- ガイドの状態：UserDefaults の `swipeDiscovery.` で始まるキー。

## 確認のしかた

- iOS：Xcode で meshinowa スキームを選び Product → Test（⌘U）。`Tests/SwipeDiscovery/` に単体テストがあります。
- Cloudflare：`npm test --prefix cloudflare`（行きたい API のテストを含む）。本番 D1 には `npx wrangler d1 migrations apply DB --remote --config wrangler.production.jsonc` で `0004_want_to_go.sql` を適用してください。
- 実機：初回ガイド（灰色とピンクの矢印、お手本の動き）、写真の軽いタップでカードが飛ばないこと、右スワイプで「行きたい」に入り「戻す」で消えること、イマイチが24時間で戻ること。
