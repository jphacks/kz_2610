# AGENTS.md

メシノワ（meshinowa）は、友達が評価したお店だけで地図を作る iOS アプリ（SwiftUI・iOS 17 以上）です。
地図と店舗検索は Google Maps / Places、友達・レビューの同期は Cloudflare を使います。

## 作業を始める前に

- 進行中の作業の状況は [docs/HANDOFF.md](docs/HANDOFF.md) にあります。最初に読んでください。
- デザインの決まり（色・形・和の入れ方）も HANDOFF に書いています。見た目を変えるときは従ってください。

## ビルドとテスト

```bash
xcodegen generate   # Swift ファイルを足したり消したりしたときだけ。生成された project.pbxproj もコミットする
xcodebuild -project meshinowa.xcodeproj -scheme meshinowa -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -project meshinowa.xcodeproj -scheme meshinowa -destination 'platform=iOS Simulator,name=iPhone 17'
```

- `GooglePlaceQueryTests` の1件は、Google のキーが入っていると実際に通信してしまうためスキップされます。
- 秘密の設定は `Config/*.xcconfig.local` に置きます（Git 対象外）。手順は [docs/GOOGLE_PLACES.md](docs/GOOGLE_PLACES.md)。
  キー・トークン・ユーザーデータはコミットやログに出さないでください。

## 書き方

- コードのコメントと UI の文言は日本語。既存のファイルの書き方（コメントの量・名前の付け方）に合わせる。
- 色とフォントは `MeshinowaTheme` / `MeshinowaFont` を使い、直接の色指定を増やさない。

## コミット

- コミット者はリポジトリのオーナー（Yuppy07）のまま。`Co-Authored-By` などの AI の署名や「Generated with」の行は付けない。
- `main` に直接コミットしない。作業ブランチを切る。
