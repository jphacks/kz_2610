# Cloudflare公開

## 方針

- ユーザー承認：公開前のセキュリティチェック後、Cloudflare公開・iOS接続先・招待リンク設定まで実施。実機2台の操作確認はユーザーが行う。
- ローカルの開発用アカウント・友達データは移さず、新しいクラウドで開始する。端末内の記録やローカルDBを削除しない。
- ブランチ：`codex/cloudflare-remote-deploy`。push・main取り込みは今回の承認に含めない。

## 公開先

- API：`https://meshinowa-api.morimo1371.workers.dev`
- Workers：`meshinowa-api`。プレビューURLは無効。開発フラグはfalse、リクエストログは無効。
- D1：`meshinowa`、migration 0001〜0007を適用。
- R2：`meshinowa-review-photos`。r2.devとカスタムドメインの公開はなし。
- 毎時の不要オブジェクト整理を有効化。
- 公開設定はGit対象外の `cloudflare/wrangler.production.jsonc`。管理用認証はWranglerが保持し、アプリには配布しない。

## アプリ

- `Config/Base.xcconfig` の標準接続先を公開APIへ変更。手元の `Cloudflare.xcconfig.local` も同じ接続先へ変更し、以前の設定はGit対象外の `cloudflare/data/deployment-backup-20261106/` に退避。
- ローカル用認証情報は残し、公開先ごとにKeychainの保存先を分ける。友達・行きたいの両方で同じ保存先を使う。新しい公開先では新規ゲストとして接続する。
- アプリに公開ホストのAssociated Domainsを設定。WorkerのAASAに既存署名チームのアプリ識別子を設定。
- ストア公開URLは未設定。招待ページはインストール済みアプリへの案内を表示する。

## 検証

- バックエンド31件成功、構文チェック成功。
- npm audit：既知の脆弱性0件。
- 公開設定でのdry-run成功、デプロイ成功。
- 公開API：`/health` は200、未認証の `/v1/me` は401、開発用 `/v1/auth/local-state` は404、AASAは200でアプリ識別子も一致。
- D1の未適用migrationなし、R2の公開URLなしを確認。
- iOS単体167件（2件スキップ・失敗0）成功。公開URLを含む実機用ビルド成功。
- 実機用アプリの接続先・署名済みAssociated Domains・署名プロファイルのアプリ識別子と権限を照合して一致。端末へのインストールは未実施。

## ユーザーによる確認

更新したビルドを2台へ入れ、別回線でゲスト接続・友達申請・承認・レビュー共有・招待リンクの起動を確認する。Macのローカルサーバーは不要。

端末に残った記録が自動ですべて移ることは今回の完了条件に含めない。新規アカウントへの過去データの一括移行は未実施。
