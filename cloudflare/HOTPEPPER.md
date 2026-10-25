# ホットペッパーの店舗画像

MapKitで見つけた店舗に、ホットペッパーグルメの掲載写真を補完します。
マップの店舗カード、詳細、検索一覧、保存一覧で利用します。架空データのデモは対象外です。

## 設定

1. [リクルートWEBサービス](https://webservice.recruit.co.jp/)で利用者本人がAPIキーを取得します。
2. `cloudflare/.dev.vars.example`を`cloudflare/.dev.vars`にコピーし、`HOTPEPPER_API_KEY`へ設定します。
   `.dev.vars`はGit対象外です。xcconfig・Info.plist・アプリコード・チャットにはキーを入れません。
3. `npm run dev --prefix cloudflare`でWorkerを起動します。
4. iOS側の`Config/Cloudflare.xcconfig.local`で`CLOUDFLARE_API_URL`をそのWorkerのoriginに設定します。
   シミュレータは`http:/$()/localhost:8787`、実機はHTTPSの開発用Workerを使用してください。
5. 本番は`cd cloudflare`の後、`npx wrangler secret put HOTPEPPER_API_KEY --config wrangler.production.jsonc`で登録します。
   既存の本番設定へ`wrangler.local.jsonc`と同じ`PHOTO_RATE_LIMITER`バインディングも追加してデプロイします。

キーまたはAPI originが未設定ならプレースホルダーを表示します。
この実装時点ではAPIキー未取得のため、実APIの写真取得は未検証です。

## 取得経路

`POST /v1/restaurant-photo`は認証不要で、JSONに`name, latitude, longitude`を指定します。
端末は表示中の店舗名と店舗座標だけを送り、現在地・レビュー・保存一覧そのもの・アカウント情報は送りません。
Workerは固定HTTPSエンドポイントへサーバー側のキーを付けてグルメサーチAPIを呼び、
`photo.pc.l`と小サイズ写真URL、店舗ページURLを返します。キー・元レスポンス全体・エラー本文は返しません。
キーを含む外部リクエストURLをログに残さないでください。リクエストの全文を記録する監視設定も避けてください。

- APIは店名と300m範囲で検索し、最大100件から照合します。
- NFKC・大文字小文字・空白・句読点の差を除いて店名が等しく、150m以内に候補が1件ある場合だけ使用します。
- 別支店、曖昧な候補、掲載なし、100件を超える候補、画像なしは`{"photo":null}`で返します。
- 画像は`imgfp.hotp.jp`、店舗リンクは`hotpepper.jp`だけをHTTPSで許可します。
- 未設定は503、上流障害は502、入力不正は400、頻度超過は429です。IP・拠点ごとに60リクエスト/分に制限します。

写真はiOSが提供元から直接取得し、D1・R2・端末ファイルへ保存しません。
Workerの応答は`private, no-store`。iOSはメモリ内だけで1時間まで再利用し、表示中も期限切れ時とフォアグラウンド復帰時に更新します。
同じ店舗の取得は共有し、同時通信は最大4件、保持は最大24店舗、画像取得は5MiBまでに制限します。
通信失敗は30秒、写真なしは5分で再試行可能になります。画像デコードはメインスレッド外で行い、長辺600px以下の表示用画像を作ります。
サムネイルから詳細へ移動しても同じ取得済み画像を使います。画像の縦横比は保ち、スクロール位置が動きにくいよう画像枠と提供表記の領域を確保します。

## 提供表記

画像直下に「画像提供：ホットペッパー グルメ」を表示します。
写真を使う画面には「Powered by ホットペッパーグルメ Webサービス」とサービスへのリンクを置き、
詳細にはホットペッパーの店舗ページへのリンクも付けます。

## 検証

```sh
npm run check --prefix cloudflare
npm test --prefix cloudflare
npm run deploy:check --prefix cloudflare
```

APIテストは架空店舗とmock応答のみを使用し、照合、別支店・曖昧候補の拒否、上流障害、キーの秘匿、頻度制限を確認します。
iOSテストではメモリキャッシュ、同じ取得の共有、期限切れ、通信障害の再試行、同時取得数、画像URL制限を確認します。
実APIの疎通は含みません。

キー設定後は実機で、掲載のある店舗の写真・提供表記・店舗リンクを確認してください。
初回表示／詳細への移動／一覧へ戻る／スクロール／圏外／バックグラウンドからの復帰／大きな文字サイズも確認対象です。
シミュレータでのビルド・テストは、実機の表示速度や外部サービスとの疎通を保証しません。

## 公式資料

- [グルメサーチAPI](https://webservice.recruit.co.jp/doc/hotpepper/reference.html)
- [提供表記と利用案内](https://webservice.recruit.co.jp/doc/hotpepper/guideline.html)
- [API利用規約](https://cdn.p.recruit.co.jp/terms/rws-t-1001/index.html)
