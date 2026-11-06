# Cloudflare公開前のセキュリティ確認（2026-11-06）

## 結果

確認範囲で未修正の重大・高リスクの問題は見つからなかった。接続先切り替え時の認証情報の共用を修正したうえで公開した。網羅的な侵入試験ではなく、実装・設定の確認、既存のアクセス制御テスト、依存関係検査、公開先の基本確認による評価。

対象はCloudflare WorkersのJavaScript API、D1/R2、招待ページ、iOSの認証情報と接続先。Workers用の専用リファレンスはスキルにないため、ソースとCloudflare公式資料に基づいて評価した。

## SEC-001：接続先変更時に開発用認証情報を共用する（中・修正済み）

- 場所：`meshinowa/Backend/GuestCredentialStore.swift:13`、`meshinowa/Models/FriendStore.swift:109`、`meshinowa/Features/SwipeDiscovery/Bridges/CloudflareWantToGoRemote.swift:12`。
- 根拠：以前はどの接続先も同じKeychain service `jp.meshinowa.app.guest` を使用していた。
- 影響：ローカル用セッショントークンを公開先へ送信し、無効なアカウントとして接続が止まる。接続先変更時の認証境界も分離されない。
- 修正：公開先のscheme・host・portでKeychainを分離し、ローカルの保存先は維持。友達と行きたいで同じ分離規則を使用する。
- 検証：接続先の違い・末尾スラッシュ・ポート・ローカル継続の単体テストを追加。
- 結果：iOS単体167件（2件スキップ・失敗0）成功。実機用ビルド成功、署名済み権限と接続先を照合済み。
- 制限：将来ドメインを変更する場合は、既存アカウントの引き継ぎ手順が必要。

## 確認した保護

- セッションは暗号学的乱数、DBに保存するのはハッシュだけ。期限と失効を毎回確認。
- SQL入力はバインドし、本人・友達・ブロック・共有同意をAPIとDB制約で確認。
- 本人用バックアップと写真を他人へ公開しない。写真は認証付きAPI経由、R2の公開URLなし。
- 入力サイズと形式を制限し、認証・招待に頻度制限。管理トークンをアプリへ配布しない。
- 招待ページは名前をHTMLエスケープし、CSP・no-store・no-referrerを設定。ストアリンクはHTTPSのAppleドメインだけ。
- 開発用APIは公開ホストで404。本番設定でも `LOCAL_DEVELOPMENT=false`。
- バックエンド31テスト成功、npm auditで既知の脆弱性0件。

## 残る運用上の条件

ゲスト認証は既存仕様どおり、セッションと引き継ぎコードの所持を本人確認に使う。Appleログインは追加していない。認証の頻度制限はIP・拠点単位の概算で、サービス全体の費用上限ではない。実機2台による共有・招待操作はユーザー確認に残す。

資料：[Cloudflare構成](https://developers.cloudflare.com/workers/wrangler/configuration/)、[D1ローカル環境](https://developers.cloudflare.com/d1/best-practices/local-development/)、[Apple Associated Domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)。
