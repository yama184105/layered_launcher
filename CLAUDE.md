# Layered Launcher - プロジェクトコンテキスト

## 概要
Flutterで開発するカスタムAndroidホームランチャーアプリ。アプリを「フロア（階層）」で整理するユニークなコンセプト。テキストのみ（アイコンなし）でスクリーンタイム削減を目指す。

## 開発環境
- Flutter / Dart (SDK ^3.11.0)
- テスト端末: Pixel 9a (Android 16)、以前は Galaxy S22。開発: Windows PC
- ローカルDB: Hive (`app_configs` box, `global_settings` box)
- ネイティブ連携: MethodChannel (`NativeService`)
- 主要パッケージ: flutter_local_notifications, android_intent_plus, google_fonts, flutter_colorpicker, image_picker, http（壁紙ギャラリー用）
- **アプリ列挙・起動・インストール検知はネイティブ実装**（`getInstalledApps` / `launchApp` / `onAppsChanged`）。開発終了した device_apps は 2026-07 に撤去済み

## アーキテクチャ
- **サービス層**: `lib/services/` - AppService(アプリ管理), SettingsService(設定、partファイルで拡張), NativeService(Android連携)
- **画面層**: `lib/screens/` - home/ と settings/ に分かれ、それぞれ parts/ でモジュール分割
- **モデル**: `lib/models/app_config.dart` - HiveObjectのAppConfig

## 設計パターン
- `part` / `part of` 構文によるファイル分割（privateアクセス維持のため。extensionではなくpart方式）
- SettingsServiceは拡張メソッド（extension）でモジュール化
- 複数のAnimationControllerによるフロア遷移アニメーション

## コーディング規約
- 日本語コメント可
- Hive設定値はSettingsServiceのgetter/setterでアクセス
- ネイティブ呼び出しはNativeServiceに集約
- UI部品はparts/フォルダにpart fileとして配置
- 未使用import/変数/メソッド削除、重複コード統合、コメントアウト削除を徹底

## フロアシステム
- 1F〜最大10F（設定で変更可能）+ 地下B1F〜B10F（負の整数）
- ホーム画面は0F（時計画面）
- フロア移動は右側ボタンのみ（スワイプでの階層移動は廃止）
- ホーム⇔1Fのみ左右スワイプ（PageView）で連続移動
- 2F以上はアニメーションで縦移動（上の階=画面上方向）
- フロアのカスタム名: `floorLabelCustom()`で設定名を優先表示

## UIレイアウト
- 「逆L字」レイアウト：アプリリスト（左）+ フロアボタン（右縦列）
- ステータスバー・ナビゲーションバー完全透明（壁紙が端まで描画）
- フォントカラーは白または黒のみ
- 壁紙にはオーバーレイ（半透明黒）で可読性確保

## ホーム画面（0F）レイアウト
1. 充電アニメーション円（内側に時刻・日付・曜日）
2. バッテリー・スクリーンタイム等テキスト
3. お気に入りアプリ（スクロール可能）
4. 電話（左）・設定歯車（中）・カメラ（右）ショートカット

## 主要機能
- **フロアシステム** (1F〜10F + 地下階)
- **モードシステム**: 全アプリが4モードのいずれかに属する（ノーマル/スケジュール/使用回数/使用時間）。詳細は下記
- **緊急モード**: 指定アプリを1Fにも表示（_emergency1FApps Set<String>で管理）。途中停止・追加可能。日/週/年の使用制限
- **マインドフルディレイ**: 起動前カウントダウン（3/5/10/30/60秒＋カスタム）。全体スイッチ `mindfulDelayEnabled` ＋ アプリ個別 `AppConfig.mindfulDelay` の AND
- **ストリクトモード**: 5サブモード（フロア移動/アニメ速度/サブモード設定/緊急使用/ショートカット変更ロック）。詳細は下記
- **通知バッチ処理**: SNS通知を指定間隔でまとめる
- **ジェスチャー制御**: 上スワイプ・下スワイプ・ダブルタップにカスタムアクション
- **アプリブロック**: 時間帯・曜日・終日・使用時間上限の組み合わせ
- **外観カスタマイズ**: フォントサイズ・行間、時計フォーマット、壁紙、フロア背景色、ステータスバー色・透明度
- **バックアップ/復元**: 設定box＋アプリ配置(AppConfig)を JSON で往復。メール送信・クリップボード・貼り付け復元。DateTime は `{'__dt': ms}` で型を保つ（`services/settings/backup_settings_part.dart`）

## モードシステム（2026-06 旧自動移動を再設計・統合）
- 全アプリが1つのモードに属する（排他）: `appMode_$pkg`（'normal'がデフォルト、キーなし＝normal）
  - **ノーマル**: 固定フロア。今までと同じアプリ一覧。手動移動のみ
  - **スケジュール**: 毎日/曜日別の時間帯スロットでフロア変更（旧自動移動モードA）。スロット外は「デフォルト」設定（既定は位置保持=keep、固定フロアも選択可）
  - **使用回数**: 1日の起動回数閾値ルール `usageCountRules_$pkg`（閾値未満は位置保持、0時リセット）
  - **使用時間**: 1日の使用時間(分)閾値ルール `usageTimeRules_$pkg`。ネイティブ `getUsageStatsToday`（UsageStatsManager）で計測
- **旧モードB（日数間隔ランダム）は廃止**。移行時はnormal（位置保持）へ
- **一時的モード（temp）**: 所属モードではなく期限つきの上書き。2種類あり排他
  - フロアの一時移動: `AppConfig.permanentFloor` + `temporaryFloorExpiry`（AppService `setTemporaryFloor` / `clearTemporaryFloor`）。期限切れで元フロアへ復帰（home_screen `_tick` が処理）
  - モードの一時上書き: `tempMode_$pkg` + `tempModeExpiry_$pkg`。期限切れで元モードへ復帰（フロアは位置保持）。`effectiveAppMode()` が期限を遅延評価
  - 一時移動中はモードエンジンを止める（`_processAutoMoves` でスキップ）。エンジン／手動移動は `setPermanentFloor` 経由で「本来のフロア」だけを更新する
- **位置保持の原則**: 割り振りなし/割り振り解除/閾値未満/一時モード終了時はフロアを動かさない
- UI: ホーム検索バー右のレイヤーアイコン → ModesScreen（**ノーマル / カスタム / 一時的** の3エントリ → 各モード内に同一設定ごとのグループ一覧）。アプリ長押し「階層を移動」→モード選択シート。**ストリクトでフロア移動ロック中のアプリは同一設定でも別グループ表示**（fingerprintにロック状態を含む）
- **複数選択**: アプリ一覧（ホーム）でもモード画面の各一覧でも長押しで複数選択でき、共通の操作バーから「フロア移動 / モード / 一時的 / 解除」を一括適用できる。カスタムのグループは見出し長押しでグループごと選択
- **対象アプリの後追い選択**: AutoMoveScreen / UsageRulesScreen のAppBar「対象 N」から、設定画面を開いたあとでも適用先アプリを複数選択で増減できる
- エンジン: home_screen `_processAutoMoves()`（毎分tick）。使用回数のみ起動時 `_trackUsageCountFloor`
- 実装: `services/settings/mode_settings_part.dart` / `screens/modes/modes_screen.dart` / `screens/modes/mode_actions.dart`（モード選択・一時的移動・アプリ複数選択の共通UI。ホームとモード画面で共用）/ `screens/settings/automove_screen.dart`（スケジュール編集）
- 移行: `migrateAppModesIfNeeded()`（settings init時、`appModesMigrated`フラグ）
- **AIコマンド機能とフロア最適化提案は削除済み**（2026-06）

## ストリクトモード（2026-07 予約変更を追加）
- サブモードごとに `block`（完全ブロック）/ `timer`（待ち時間つき）を選ぶ。**待ち時間は `strictSubTimerMinutes(key)` が全経路で使われる**（以前はタイマーダイアログもクールダウンも10秒固定だった）
- **予約変更**: ロックされた変更を今すぐではなく指定時間後（既定60分）に自動適用する。ONだとゲートで「今すぐ待つ / 予約する」を選べる
  - 保存: `strictReservations`（List<Map>）。種類は `ReservationKinds` を参照
  - 適用: home_screen / settings_screen の `_tick` が `applyDueStrictReservations(appBox)`
  - 予約状況・キャンセルは設定→ストリクトモードの「予約の状況」から `StrictReservationsScreen`
  - ショートカット変更だけは payload を持ち回せないのでタイマーのみ（予約非対応）
- **共通ゲート**: `screens/strict/strict_gate.dart` の `requestStrictAction()` がホーム・モード画面・設定から共用。戻り値 allowed / reserved / denied
  - `treatBlockAsTimer`: サブモード設定ロック自身を変えるときだけ true。完全ブロックでも待ち時間か予約でなら通す（**でないと二度と解除できない状態になる**）
- **フロア移動ロック**: 対象アプリの**追加は即時**、対象を減らす（＝ロックを緩める）変更はゲート経由。対象リストが空＝全アプリなので、そこから絞るのも緩和扱い
- ロック中アプリのフロア移動もゲート経由（待つか予約）。複数アプリ同時は `floorMoveBulk` として1件の予約にまとまる
- **緊急使用設定ロック**は緊急使用の上限（全体/一覧/登録全体/アプリ個別/フォルダ）と緊急アプリの登録の変更をゲートする。以前あった「対象アプリ」選択は `isEmergencyLocked` がどこからも呼ばれておらず無意味だったため削除
- **予約できる操作**: フロア移動（単体/複数）/ ロック対象の変更 / ストリクト各設定 / 緊急使用の上限（全体・一覧・登録全体・アプリ個別・フォルダ）/ 緊急アプリの登録 / アニメーション速度（全体・フロア間・一括解除）
- **レガシーロックモードは廃止**（2026-07）。`lockMode` + `pendingFloorMap` + 10秒クールダウンの旧系統を削除し、`migrateLegacyLockIfNeeded()` でストリクトへ移行（起動時に main.dart から1回）
- **フロア移動は必ず `applyFloorsWithStrictGate()` を通す**。ホーム・モード画面・アプリ管理・ランダム配置すべて同じ経路（直接 `app.floor = x` と書かないこと）
- 毎秒の tick は `nextReservationDueMs`（キャッシュ済みの次回適用時刻）だけを見る。予約リストの全件パースはしない
- 実装: `services/settings/reservation_settings_part.dart` / `services/settings/block_settings_part.dart` / `screens/strict/strict_gate.dart` / `screens/settings/parts/security_settings_part.dart`

## アニメーション
- 種類: none / slide / fade / zoom / stair
- 速度: 10段階（50ms〜3000ms）+ カスタム（50〜5000ms）
- 壁紙+コンテンツを1ボックスとして統合スライド方式
- フロア間ごとの個別速度設定 + 一括変更オプション

## 設定画面設計
- Minimalist Phone方式：項目名1行→タップでダイアログ
- アコーディオン式（1つ開くと他は閉じる）
- 現在値を項目名の右に小さく表示

## テスト
- `test/settings_service_test.dart` — サービス層（UI非依存）のユニットテスト。モード/一時モード期限/ストリクト待ち時間/予約の適用・置換・キャンセル/レガシー移行/バックアップ往復
- Hive は `Directory.systemTemp` に `Hive.init()` して毎テスト作り直す

## 既知の未解決課題
- Androidホームボタンでホーム画面に戻る機能（AndroidManifest.xml HOME intent）
- Galaxyの「マイファイル」が表示されない（`_forceIncludeApps` で個別に拾っている）
- 設定画面の壁紙透明度変更が反映されない
- オンライン壁紙ギャラリーは `unsplashAccessKey` がプレースホルダのまま＝必ず401
- `invalid_use_of_protected_member` 111件は part+extension から setState を呼ぶ構造上のもの（動作には影響なし）

## 開発メモ
- 変更履歴や決定事項はここに追記していく
