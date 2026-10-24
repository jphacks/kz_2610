# meshinowa（メシノワ）

おいしい店は、友達が知っている。

友達のおすすめを地図から探す、iPhone向けアプリです。
iOS 17以上・SwiftUI・MapKit・Supabaseを使って、少しずつ開発します。

## 開発環境

- Xcode（iOS 17以上のSDK）
- iOSシミュレータ
- XcodeGen（プロジェクト構成を変更する場合のみ）

## 起動方法

1. `meshinowa.xcodeproj` をXcodeで開く。
2. `meshinowa` スキームとiPhoneシミュレータを選ぶ。
3. Runで起動する。

実機で動かす場合は、XcodeのSigning & Capabilitiesで自分のTeamを設定してください。
Bundle Identifierは仮の値です。

プロジェクト構成は `project.yml` で管理しています。
構成を変更したら、XcodeGenが入った環境で `xcodegen generate` を実行し、
生成されたプロジェクトも一緒にコミットしてください。

## 現在の状態

歓迎画面だけの、開発を始めるための土台です。
地図・認証・データ保存はこれから実装します。

## 公開リポジトリでの開発

秘密情報、個人情報、実ユーザーのデータはコミットしません。
接続設定が必要になった時点で、ローカル設定と公開可能なサンプルを用意します。
