# Supabaseの土台（⑭）

## 現在の状態

- migrationは専用の新規開発プロジェクト向けです。2026-10-24にクラウド開発DBへ初回定義を適用済みです。
- Swift SDKは2.55.4に固定しています。接続設定とクライアント生成の入口を用意しました。
- ログイン・端末内データの同期は⑮・⑱で追加します。今回の追加だけではレビューや写真を送信しません。

### 初回適用の確認記録（2026-10-24）

適用前に既存アプリテーブル・Storageバケットが0件であることを確認しました。
DBへの直接接続が待機したため、その処理を停止し、管理API経由の `supabase db query --linked --file` で
初回migrationを適用しました。反映確認後に `supabase migration repair 20261024000100 --status applied --linked` で履歴を登録しています。

- アプリ用11テーブルすべてでRLS有効、アプリ用ポリシー20件。
- 公開スキーマのRPCは9件で、`anon` に実行権限なし。
- 写真用Storageポリシー3件、バケットは非公開・JPEGのみ・5MiB上限。
- Authのユーザー作成時にプロフィールを生成するトリガーを確認。
- ローカルDB権限テスト18件成功。実アカウントでのログイン・友達操作・写真転送の確認は後続実装時に行います。

## アプリ側の設定

`Config/Supabase.example.xcconfig` を `Config/Supabase.xcconfig.local` にコピーし、URLとpublishable keyを設定します。
ローカル設定はGitで無視され、Xcodeのビルド時にだけ読み込みます。
URL内の `/$()/` はxcconfigのコメント解釈を避ける記法なので、そのまま残してください。
設定なしでも端末内機能は動きます。設定が片方だけ・不正な場合は、クライアント生成時にエラーになります。

アプリには `sb_publishable_` のキーだけを使用します。キーは配布アプリから読めるため、非公開データはRLSで保護します。
secret key・service_role・DBパスワード・管理用アクセストークンはアプリやGitに入れません。

## DB・Storageの設計

| 対象 | 方針 |
|---|---|
| profiles | メールを格納せず、表示名・IDなどだけ。検索は初期状態でOFF |
| profile_preferences | 検索許可・来店日公開・地図の平均評価への参加。本人だけ読み書き |
| friend_requests / friendships | 申請は双方だけ読める。受信者の承認RPCだけが対称の友達ペアを作る |
| favorite_friends | 自分側だけのお気に入り。承認済みの友達のみ登録可能 |
| blocks | 自分のブロックだけ読める。RPCで関係・申請・双方のお気に入りを解除 |
| restaurants | 店舗位置・名前のキャッシュ。認証後に追加可能、クライアントから既存情報を改変しない |
| reviews | 本人か承認済みの友達だけ。1人1店1件、1〜5・0.5刻み、コメント300文字 |
| review_visits | 来店日を分離し本人だけ直接取得。友達向けRPCは公開設定に従って日付を隠す |
| review_photos | レビュー所有者と複合外部キーでひも付け。1〜5のslotの一意制約で同時投稿でも最大5枚 |
| saved_restaurants | 本人だけ。行きたい／行ったは排他、お気に入りは独立。レビュー投稿と同じトランザクションで行ったへ移動 |

写真バケット `review-photos` は非公開・JPEGのみ・1枚5MiBまでです。
まず写真メタデータのslotを作成し、返された `object_path` にStorage APIでアップロードします。
パスを知っているだけでは他人の写真を読めません。解除・ブロック時に読み取り権限を失います。
⑱の実装では認証付きダウンロードを使用してください。権限変更前に発行済みの署名URLを長期利用しない設計にします。
既にダウンロードした写真を他人の端末から取り消すことはできません。
レビューやメタデータの削除後は、元の所有者がStorage APIで残存ファイルを削除できます。
ファイルそのものの削除はStorage API経由で行い、`storage.objects` のSQL削除で代用しません。

### RPC

- `send_friend_request(target_id)`
- `respond_friend_request(request_id, accept)`
- `cancel_friend_request(request_id)`
- `remove_friend(other_id)`
- `block_user(other_id)` / `unblock_user(other_id)`
- `friend_ratings(friend_ids, min_lat, min_lng, max_lat, max_lng)`
- `friend_review_details(target_restaurant)`
- `save_my_review(target_restaurant, new_rating, new_comment, new_dish, new_want_again, new_visited_on)`

集計は実際の承認関係・ブロック・地図への評価表示設定で再チェックします。
`friend_ids = null` は友達全員、空配列は対象0人です。日付非公開設定は平均への参加設定とは独立です。
`private` スキーマはData APIに公開しないでください。内部関数は固定search_path・必要最小限の実行権限です。

## ローカルの権限テスト（Docker不要）

```sh
npm ci --prefix backend-tests
npm test --prefix backend-tests
```

PGliteのPostgresに本番用migrationを変更せず適用し、`anon` / `authenticated` ロールを切り替えてテストします。
Authの検証済みユーザーIDとStorageメタデータの最小スキーマはテスト用に再現しています。
実際のAuth HTTP認証・Storageのファイル転送・JWT検証・クラウドの設定まで検証するものではありません。
テスト用ユーザーとデータはメモリ内だけに作成します。`backend-tests/bootstrap.sql` はクラウドに実行しません。

Docker環境がある場合は `supabase start` で実際のローカルSupabaseを起動できます。
`supabase db reset --local` はローカルDBを初期化するコマンドです。

## クラウドへの適用

この作業には対象プロジェクトへの管理権限が必要です。publishable keyだけではDDLを実行できません。
共同開発者に、自分のSupabase登録アカウントを対象の組織へ招待してもらい、招待を受諾してください。
CLIのログイン情報は自分の端末で設定し、チャットやGitで共有しません。

対象が専用の新規開発DBであることを確認してから、次の順で進めます。

```sh
supabase projects list
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --dry-run
supabase db push
```

CLIからDBパスワードを求められた場合は、自分のターミナルで入力します。
⑭の初回migrationは既存テーブルを削除しません。同名のテーブルが既にある場合は適用を止め、差分を確認します。

管理権限を共有しない場合は、共同開発者がSQL Editorで `migrations/20261024000100_initial_schema.sql` の全体を実行できます。
この方法ではCLIのmigration履歴は自動記録されません。後からCLIで管理するときは、適用成功とスキーマを確認してから、
`supabase migration repair 20261024000100 --status applied` で履歴を一致させます。未適用なのにrepairしないでください。

適用後はTable Editorで全対象のRLS、Storageの非公開設定を確認し、別々の実アカウントで承認・解除・ブロックを通したテストを行います。
ユーザー削除時のStorageファイルの片付け、通報・レート制限・運用監視は、今後のアカウント削除・公開準備で追加します。

## 参照

- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/docs/guides/getting-started/api-keys
- https://supabase.com/docs/reference/swift/initializing
