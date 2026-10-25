# Google Mapsと店舗写真

アプリ内の地図はGoogle Maps SDK for iOS、店舗検索・写真はPlaces API (New)を使用します。
Places UI Kitのカードは撤去し、写真をアプリの画像枠に表示します。
MapKitの型は既存の保存・レビュー処理との互換用データとしてのみ使用し、Appleの地図や店舗検索は呼び出しません。

## 設定

1. 同じ[Google Cloudプロジェクト](https://console.cloud.google.com/)で課金を設定し、次を有効化します。
   - [Maps SDK for iOS](https://console.cloud.google.com/apis/library/maps-ios-backend.googleapis.com)
   - [Places API (New)](https://console.cloud.google.com/apis/library/places.googleapis.com)
2. APIキーのアプリケーション制限を「iOSアプリ」、Bundle IDを `jp.meshinowa.app` に設定します。
   API制限では上の2つを許可します。Places UI Kit APIは使用しません。
3. `Config/GooglePlaces.example.xcconfig`を`Config/GooglePlaces.xcconfig.local`へコピーし、
   `GOOGLE_PLACES_IOS_API_KEY`にキーを保存します。既存のローカルキーはそのまま使用できます。
4. 再ビルドしてインストールします。設定ファイルの編集だけではインストール済みアプリに反映されません。

ローカル設定はGit対象外です。キー・リクエスト・ユーザーデータをログやコミットに含めません。
iOS用のキーは配布アプリから読み取れるため、Google Cloud側のアプリ制限・API制限・クォータで保護します。
Cloudflareのsecretは不要です。キー未設定では地図・検索は利用できず、端末の保存・レビュー画面は利用できます。

## 動作と制約

- Google Maps / Placesの公式SDKを11.2.0に固定しています。
- 地図ホーム、保存一覧、マイマップ、友達デモのすべての地図をGoogle Mapsに統一します。
- 検索は表示範囲のテキスト検索で最大20件。店名検索は表示範囲を位置バイアスに使います。
- 営業中フィルターは使いません。ジャンルはGoogleの店舗タイプを既存カテゴリへ変換します。
- 新しい検索結果はPlace IDで写真を取得します。保存・レビューにはPlace IDを追加し、既存JSONも読み込めます。
- 移行前の保存店舗は店名・住所を使って照合し、300m以上離れた結果は写真に使いません。
  提供元が異なるため、昔の保存店舗と新しい検索結果の名前・座標の差で同一店舗と判定できない場合があります。
- 選択中の写真を優先して取得し、その後に左右1店舗ずつを先読みします。周回境界も対象にし、同じ店舗への重複リクエストを共有します。
- カルーセル・一覧・詳細で写真と必須クレジットを共有します。表示セッション用メモリは最大24MB・24件、写真は2分、写真なしは30秒で期限切れにし、メモリ警告時に解放します。
- 同時取得は最大3件に制限し、待機中の表示用リクエストを先読みより優先します。写真は表示前にデコード準備を行います。
- SDK標準のHTTPキャッシュを利用します。独自ディスクキャッシュ・R2/D1保存・写真参照名の永続保存・プロキシ再配信は行いません。
- Googleカードの枠・店名・住所の重複表示はありません。
  写真の下には必須のGoogle Maps提供表記・撮影者名・提供者のリンクを表示します。
  Google Mapsのロゴ・著作権表示はカードに隠れないよう地図の余白で確保します。
- 写真がない店舗はプレースホルダー、通信エラーは再読込ボタンを表示します。
- 経路ボタンはGoogle Mapsの徒歩経路を開きます。
- ユーザーの現在地は取得しません。検索語・閲覧範囲・店舗IDだけをGoogleへ送り、レビュー本文・ユーザー情報を送りません。

地図・検索・写真には通信とGoogle Cloud側の設定が必要です。利用量に応じた料金・クォータはCloud側で確認します。
公開前にはGoogleが要求する利用規約・プライバシーポリシーとSDKライセンスの掲載も確認してください。

## 検証

Xcodeのmeshinowaスキームでテストを実行します。
キー形式、旧店舗照合クエリ、ジャンルの変換、営業時間を限定しない検索、Place IDの保存互換性を検証します。
実APIは東京駅周辺で、地図タイル・検索結果・ピン選択・カルーセル・一覧・詳細の写真とクレジットを確認します。
APIキーなしの描画テストはキー設定済みの環境ではスキップし、実表示は別に確認します。
実機では地図の移動・拡大、カードの往復、大きな文字、低速通信・圏外・再試行も確認してください。

## 公式資料

- [Google Maps SDK for iOS](https://developers.google.com/maps/documentation/ios-sdk/map)
- [Text Search (New)](https://developers.google.com/maps/documentation/places/ios-sdk/text-search)
- [Place Photos (New)](https://developers.google.com/maps/documentation/places/ios-sdk/place-photos)
- [表示・クレジット要件](https://developers.google.com/maps/documentation/places/ios-sdk/policies)
