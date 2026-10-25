# Cloudflareバックエンド

WorkersがHTTP API・認証・認可を担当し、D1にアプリデータ、非公開R2にレビュー写真を保存します。
Swift側は`URLSession`を使い、Cloudflare管理トークン・R2アクセスキーをアプリへ配布しません。
URLを設定するとアプリはゲストアカウントを作り、レビューの評価・ひとこと・おすすめ料理を友達に共有します。写真・来店日・保存一覧は送信しません。お店スワイプの「行きたい」だけは本人専用の一覧として同期します。

## ローカル開発

Node.js 22以上が必要です。リポジトリのルートで実行します。

```sh
npm ci --prefix cloudflare
npm run check --prefix cloudflare
npm test --prefix cloudflare
npm run db:local --prefix cloudflare
npm run deploy:check --prefix cloudflare
npm run dev --prefix cloudflare
```

`wrangler.local.jsonc`のDB IDはローカル専用のダミーです。状態はGit対象外の`.wrangler/`に保存されます。
本番への接続や既存データの読み取りは行いません。ログイン不要で実行できます。

iOS側は`Config/Cloudflare.example.xcconfig`を`Config/Cloudflare.xcconfig.local`にコピーし、
`CLOUDFLARE_API_URL`にAPIのoriginを設定します。未設定なら端末内モードです。
HTTPはlocalhost・loopback、またはDebugビルドの`.local`ホストだけ許可します。実機用の同一Wi-Fi中継は末尾の手順を参照してください。公開ホストにはHTTPSを使用します。

## iOSの店舗カード

写真はGoogle Places公式SDKで取得し、iOSアプリ独自の画像枠と必須クレジットで表示します。
[設定手順](../docs/GOOGLE_PLACES.md)を参照してください。Cloudflareには写真検索・写真プロキシAPIを設けていません。

## 認証（ゲスト）

ハッカソン版のため、ログイン画面とSign in with Appleは使いません。

1. アプリの初回起動時に`POST /v1/auth/guest`へ`{"display_name":"…"}`（省略時は「ゲスト」）を送る。
2. Workerがユーザー・プロフィール・既定設定・365日セッションを生成し、`access_token`を返す。
   IDは紛らわしい文字を除いた英小文字・数字7文字で、友達がIDで見つけられるよう`allow_id_search`を有効にする。
3. 以後`Authorization: Bearer <access_token>`を送る。`DELETE /v1/auth/session`でそのセッションを失効する。

通常の認証にはセッショントークンを使用します。iOSはKeychain（この端末のみ）に保存し、失った場合は事前に発行した引き継ぎコードで復旧します。
設定から引き継ぎコードを発行・再発行し、別端末へ引き継げます。コードはサーバーにSHA-256のみを保存します。アカウント削除画面も実装しています。
D1にはセッショントークンのSHA-256のみを保存します。
ゲスト作成には今までの認証POSTと同じCloudflare Rate Limitingを使用します（IP・拠点ごとに20回/分、概算）。

## データとアクセス制御

D1はPostgres RLSを提供しないため、DBへのアクセスはWorkerのバインディングだけに限定します。
SQLやテーブル名を指定できる汎用APIはありません。書き込み時の所有者はセッションから決定します。

- 店舗: 認証なしで指定範囲内を取得可能。作成は認証必須。同じ`external_key`は既存店舗を返し、他人の店舗情報を上書きしない。
- プロフィール: 本人、友達、ID検索許可、申請中の相手のみ。検索はhandleの完全一致。ブロックは相互に非表示。
- 設定・保存・お気に入りの友達: 本人だけが読み書き可能。
- 行きたい（`want_to_go`、お店スワイプの右スワイプで追加）: 本人だけが読み書き可能。レビューの作成・更新時にトリガーで外す。
- 友達関係: 受信者がpending申請を承認した場合だけ生成。申請の直接編集や関係の直接作成を公開しない。
- 解除・ブロック: 関係・両方向のお気に入り・申請を同じSQL処理内で削除。解除しても関係は復活しない。
- レビュー・写真: 本人と承認済みの友達のみ。ブロック・解除後は毎回最新のD1状態で拒否。
- 来店日: 別テーブルに保持し、友達への返却は`show_visit_date`に従う。
- Friend Lens: 承認済みかつ`include_in_friend_avg`が有効な友達だけを集計。選択なしと空配列を区別する。
- レビュー更新: 1人1店舗、0.5刻みの1〜5、コメント300文字、料理100文字。来店日更新と「行った」への移動をD1 batchで一括実行。お気に入りは保持。

関係の競合はD1の単一書き込み処理とトリガーで制約します。
D1のread replicationは有効化しない構成です。有効化する際は、失効・ブロック直後の認可が古い状態を参照しないよう再設計してください。
配列の応答は最大1000件、Lensの指定IDは最大100件です。一覧は`limit`（1〜1000、既定1000）と`offset`（0以上、既定0）に対応します。iOSは1000件ずつ全ページを取得します。
地図の経度範囲はmin≤maxで、日付変更線をまたぐ範囲は二分して取得します。

## API

JSONのキーはsnake_case。特記のないAPIは認証必須です。書き込み成功は200、作成は201です。

| メソッド・パス | 入力・用途 |
| --- | --- |
| `GET /health` | 認証不要のプロセス生存確認。DB/R2の疎通確認ではない |
| `POST /v1/auth/guest` | 認証不要。`display_name?`でゲストアカウントとセッションを作成 |
| `DELETE /v1/auth/session` | 現在のセッションを失効 |
| `GET, PATCH /v1/me` | 本人のプロフィール。更新は`display_name, handle` |
| `GET, PUT /v1/preferences` | 更新は`allow_id_search, show_visit_date, include_in_friend_avg`（全てboolean） |
| `GET /v1/profiles?handle=…` | handleの完全一致検索 |
| `GET /v1/profiles/:id` | 閲覧可能なプロフィール |
| `GET /v1/friends` | 友達と本人の`is_favorite` |
| `GET, POST /v1/requests` | 申請一覧（双方の表示名・ID付き）／送信。作成は`target_id` |
| `PATCH, DELETE /v1/requests/:id` | 受信者が`accept`で回答／送信者がpendingを取消 |
| `DELETE /v1/friends/:id` | 友達を解除 |
| `PUT, DELETE /v1/friends/:id/favorite` | お気に入りの友達を追加・削除 |
| `GET /v1/blocks` | 本人がブロックしたID |
| `PUT, DELETE /v1/blocks/:id` | ブロック・解除 |
| `GET /v1/restaurants` | 認証不要。範囲パラメータ必須 |
| `POST /v1/restaurants` | `external_key, name, latitude, longitude, category?, address?` |
| `GET /v1/ratings` | 範囲と任意の`friend_ids`（カンマ区切り）。省略で全員、空文字で0人 |
| `GET /v1/reviews?restaurant_id=…` | 本人と友達のレビュー。来店日は設定に従う |
| `GET /v1/friend-reviews` | 友達のレビューを店舗情報・投稿者名付きで新しい順に返す（平均に含めない設定の友達は除く） |
| `GET /v1/me/reviews` | 本人のレビュー一覧 |
| `PUT /v1/reviews` | `restaurant_id, rating, comment?, dish?, want_again?, visited_on?`。省略来店日は削除 |
| `DELETE /v1/reviews/:id` | 本人のレビューを削除 |
| `GET /v1/saved` | 本人の保存一覧 |
| `PUT, DELETE /v1/saved/:restaurant_id` | 更新は`status`（null / want_to_go / visited）, `is_favorite` |
| `GET /v1/want-to-go` | 本人の「行きたい」を店舗情報付きで新しい順に返す（いいね・保存一覧とは別） |
| `PUT, DELETE /v1/want-to-go/:restaurant_id` | 「行きたい」に追加・削除。追加済みなら日時を保つ。レビューを書くと自動で外れる |
| `GET /v1/photos?review_id=…` | 閲覧可能な写真メタデータ |
| `POST /v1/photos` | 本人のレビューに`review_id, slot`（1〜5）で枠を予約 |
| `DELETE /v1/photos/:id` | 本人の枠とR2オブジェクトを削除 |
| `GET, PUT, DELETE /v1/objects/:owner/:review/:photo.jpg` | 認証付き写真取得・アップロード・削除 |

範囲パラメータは`min_lat, min_lng, max_lat, max_lng`。
D1のboolean列は応答では0/1です。入力にはJSON booleanを使用します。
認証失敗は401、入力不備は400、見えない対象は404、DB制約違反は409、容量超過は413、形式違いは415、認証頻度超過は429。
エラーにはSQL・入力値・認証情報を含めず、Workerでリクエストや本文をログ出力しません。

## 写真

予約で返された`object_path`に対し`PUT /v1/objects/<object_path>`で送信します。
本人所有の予約枠が必要で、最大5枚・各5MiB・`image/jpeg`のみ。
WorkerはサイズとJPEG開始・終端を確認しますが、完全な画像デコードやEXIF除去は行いません。
iOSは既存の`ReviewPhotoCodec`でメタデータを除去したJPEGを渡してください。
R2の公開URL・r2.dev・公開カスタムドメインは有効にしません。取得は必ず認証付きWorker経由です。
応答は`Cache-Control: private, no-store`。署名付きURLは発行せず、関係を解除した後も使えるURLを残しません。

D1とR2を跨ぐ原子的なトランザクションはありません。レビュー削除時には写真メタデータがcascadeで消え、
残存R2オブジェクトは誰にも閲覧されません。所有者は枠が消えた後もobject APIで残存ファイルを削除できます。
アップロードと削除が競合した場合やR2削除が失敗した場合も同様です。1時間ごとのscheduledハンドラーで100件ずつ走査し、24時間以上経過してメタデータから参照されないオブジェクトを削除します。走査cursorはD1に保存し、大きなバケットでも次回に続けます。

## 本番設定とデプロイ

この変更では本番リソースの作成、既存クラウドの削除、実データの移送、デプロイを行っていません。
対象Cloudflareアカウントで認証し、専用のD1と非公開R2を作成してから適用します。
実際のアカウントID・DB ID・ホスト名はGit対象外の`wrangler.production.jsonc`に設定します。

```sh
cd cloudflare
npx wrangler login
npx wrangler d1 create meshinowa
npx wrangler r2 bucket create meshinowa-review-photos
cp wrangler.local.jsonc wrangler.production.jsonc
```

コピーした設定のDB IDを作成結果へ置き換えます。
専用APIのカスタムドメインを設定するか、開発用に`workers_dev: true`を明示します。
`observability.enabled: false`を維持し、認証情報を含むログを有効にしないでください。

```sh
npx wrangler d1 migrations apply DB --remote --config wrangler.production.jsonc
npx wrangler deploy --dry-run --config wrangler.production.jsonc
npx wrangler deploy --config wrangler.production.jsonc
```

デプロイ後、HTTPS originをローカルxcconfigへ設定し、2台の端末（またはシミュレータ）のゲストで申請・承認・解除・ブロックを確認します。
管理トークンはWranglerの認証情報またはCIのsecret管理に置き、`.dev.vars`やチャット、コミットへ貼り付けません。

既存Supabaseに実データがある場合は、新規ユーザーで置き換える前に[移行手順](MIGRATION.md)を確認してください。

## 検証範囲

`npm test`は一時D1/R2をMiniflareで起動し、NodeからWorkerハンドラーを実行します。
本番用migrationを適用し、権限・同時操作・写真転送・JWT署名検証・セッション発行を検証します。
認証の頻度制限は単体テストではstubに置き換えます。
`db:local`でWrangler経由のmigration適用、`deploy:check`でWorkers用bundleを確認できます。
iOS側はURLProtocolを使い、設定・送信先・認証ヘッダー・エラーの秘匿を検証します。
本番Cloudflare設定・実機の疎通はこれらのテストに含まれません。

## 公式資料

- [D1 batchとトランザクション](https://developers.cloudflare.com/d1/worker-api/d1-database/)
- [D1の外部キー](https://developers.cloudflare.com/d1/sql-api/foreign-keys/)
- [R2 Workers API](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/)
- [Workers Rate Limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)


## プロフィール・バックアップ・引き継ぎAPI（migration 0004）

| メソッド・パス | 用途 |
| --- | --- |
| `PATCH /v1/me` | `display_name, handle`と任意の`bio`（160文字）, `avatar_symbol`（アプリの8種類） |
| `DELETE /v1/me` | 本人のアカウントをcascade削除し、セッション・引き継ぎコード・バックアップを失効 |
| `POST /v1/me/recovery-key` | 新しい64桁のコードを返す。再発行で以前のコードは無効 |
| `POST /v1/auth/recover` | 認証不要。`recovery_key`で同じアカウントのセッションを発行。認証POSTの頻度制限を適用 |
| `GET /v1/library` | 本人専用の`version, snapshot`。未作成はversion=0、snapshot=null |
| `PUT /v1/library` | `version, snapshot`。version一致時だけ更新し、競合は409。schema=1、saved/reviews配列。メタデータ最大1.5MB、超過は413 |
| `GET, PUT /v1/library/photos/:uuid.jpg` | 本人専用のJPEGバックアップ（各5MiBまで） |

通常のレビュー共有では写真・来店日を送信しません。バックアップボタンを押した場合だけ、保存・レビュー・写真・来店日を本人専用の領域に保存します。
バックアップは常時自動同期ではありません。復元前に全写真を取得・検証し、ローカル変更の失敗時は元の記録に戻します。
他ユーザーや友達からバックアップを読めるAPIはありません。引き継ぎコードを持つ人は同じ本人として認証されるため、コードを第三者へ共有しないでください。
R2残存オブジェクトはアカウント削除と同時に閲覧不可となり、定期処理で物理削除します。

`POST /v1/restaurants`は任意の`google_place_id`も受け付け、同じPlace IDなら既存の店舗を返します。旧external_keyは保持します。
新APIを利用する接続先にはmigration 0004とWorker更新の両方を適用してください。


## ローカルDBを作り直した後の認証

`GET /v1/auth/local-state`は`LOCAL_DEVELOPMENT=true`かつlocalhost/loopbackホストの場合だけ利用できます。永続的なDB識別子と、ユーザーが0件かどうかを返します。公開ホストでは404です。
iOSは401を受けたとき、このDBが空、または端末が記録した開発DBの識別子と異なることを確認できた場合だけゲスト接続を作り直します。端末の保存・写真・レビューは削除せず、レビューを共有待ちへ戻します。
同じDBでセッションだけが無効になった場合や、本番サーバーの401ではアカウントを勝手に作り直しません。再認証・引き継ぎが必要なことを表示します。


## 同じWi-Fiの実機から接続する開発ビルド

MacとiPhoneを同じWi-Fiへ接続し、まず通常の`npm run dev`でWranglerをlocalhost:8787に起動します。
HTTPを使う開発ネットワークでの通信に同意している場合、アプリAPIだけを転送する中継を起動します。

```sh
python3 cloudflare/dev-device-proxy.py --bind <MacのWi-FiのIPv4アドレス>
```

`Config/Cloudflare.xcconfig.local`には次のSDK条件付き設定を追加できます。Macのホスト名は`scutil --get LocalHostName`で確認します。

```xcconfig
CLOUDFLARE_API_URL[sdk=iphoneos*][config=Debug] = http:/$()/YOUR-MAC.local:8788
```

この設定はシミュレータ用のlocalhost設定に影響しません。`.local`宛のHTTP接続はDebugビルドだけが受け付けます。
iPhoneでローカルネットワークへのアクセスを許可してください。Macとサーバー・中継の起動が必要です。
中継は`/health`と`/v1/`だけを扱い、Wrangler Local Explorerや管理APIをLANへ出しません。リクエスト本文や認証情報はログに記録しません。
このHTTP中継は認証情報とアプリのデータを暗号化しません。許可された開発ネットワークに限って使用してください。公開ホストの接続にはHTTPSを使用します。
