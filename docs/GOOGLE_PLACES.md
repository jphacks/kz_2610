# Apple地図とGoogleの店舗カード

地図・店舗検索・保存の基準はMapKitのまま、写真とGoogleの店舗名・住所をGoogle公式Places UI Kitのカードで表示します。
Googleの写真URLを取り出して独自の画像枠に表示する実装や、写真プロキシAPIはありません。

## 必要な設定

1. [Google Cloud](https://console.cloud.google.com/)でプロジェクトと課金を設定します。
2. [Places UI Kit API](https://developers.google.com/maps/documentation/places/ios-sdk/places-ui-kit-get-started)を有効にします。
3. iOSアプリ用のAPIキーを発行し、アプリケーション制限をBundle ID `jp.meshinowa.app` に設定します。
   API制限は利用するPlaces UI Kitに限定します。Cloudflare管理トークンやサーバー用キーをアプリへ設定しません。
4. `Config/GooglePlaces.example.xcconfig`を`Config/GooglePlaces.xcconfig.local`へコピーし、
   `GOOGLE_PLACES_IOS_API_KEY`へキーを設定します。ローカル設定はGit対象外です。
5. Xcodeから再ビルドします。キー未設定でも地図・検索・保存・レビューは動き、写真部分はプレースホルダーになります。

ネイティブSDKはiOS制限付きキーをアプリから使用するため、配布済みアプリ内からキーを完全に秘匿する構成ではありません。
ソース・Git・チャットへは貼り付けず、Google Cloud側のアプリ制限・API制限・クォータで保護します。
写真のためにCloudflareのsecretを設定する必要はありません。

## 動作

- SDKはGoogle公式 `googlemaps/ios-places-sdk` の11.2.0に固定しています。
- Googleの`PlaceSearchView`を使用し、MapKitの店名・住所・店舗座標でテキスト検索します。
- 検索の位置バイアスは店舗から300m。表示は最大1件で、営業時間による絞り込みはしません。
- Googleカード内の店舗名・住所も表示します。別の候補が返る可能性があるため、Googleの検索結果であることを名前・提供表記を含むカードで明示します。
- 地図のカルーセルは現在選択中のカードだけGoogleを読み込みます。周回表示の複製カードを事前取得しません。
- 写真・提供元・投稿者・リンクはSDKが表示します。Googleの表記やリンクを覆ったり削除したりしません。
- 独自の写真ダウンロード・再配信・D1/R2保存・写真参照名のキャッシュは行いません。
- リクエストは表示中の店舗の公開情報だけを使用します。レビュー本文・保存一覧全体・アカウント情報・ユーザーの現在地を渡しません。
- Googleの検索・表示処理はUI Kit内で完結し、通常のPlaces APIで取得した写真をApple地図へ載せません。
- APIエラー時は写真部分に再試行を表示します。SDKのエラー本文やキー、リクエスト内容をアプリでログ出力しません。

Places UI Kitには、非Google地図との併用を認める明示的な例外があります。
写真を独自に取得する通常のPlaces APIとは利用条件が異なるため、UI Kitを迂回する構成へ変更しないでください。

UI Kitはカードの表示・再検索に応じて課金されます。`@State`で検索リクエストを保持し、通常のView再描画で再検索を発生させません。
Google Cloudの料金・クォータを確認してから利用します。画面の再表示や手動再試行では新しいリクエストになり得ます。

## 検証

Xcodeのmeshinowaスキームでユニットテストを実行できます。
設定キーの検証、店舗情報からのクエリ生成、営業時間を限定しないこと、検索リクエストの安定性、未設定時の描画を確認します。
バックエンドのテストとビルドは従来どおり`npm test --prefix cloudflare`と`npm run deploy:check --prefix cloudflare`です。

APIキーを設定したら東京駅周辺の実際のMapKit検索結果で、Googleの写真・店舗名・住所・提供表記・リンクを確認します。
Googleに店舗・写真がない場合や異なる候補の場合もあり、全店舗で写真が出る保証はありません。
実機ではカルーセル・一覧・詳細の往復、大きな文字、低速通信、圏外、再試行、Googleカード内のリンク操作も確認してください。
キー未設定のテストやシミュレータ上のビルド成功を、実APIの取得率や実機性能の確認の代わりにはしません。

## 公式資料

- [Places UI Kitの非Google地図との併用条件（15.1）](https://cloud.google.com/maps-platform/terms/maps-service-terms#places-ui-kit)
- [iOS Places UI Kit](https://developers.google.com/maps/documentation/places/ios-sdk/places-ui-kit-overview)
- [Place Searchコンポーネント](https://developers.google.com/maps/documentation/places/ios-sdk/place-search-ui-kit)
- [設定手順](https://developers.google.com/maps/documentation/places/ios-sdk/places-ui-kit-get-started)
- [利用量・料金](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing)
