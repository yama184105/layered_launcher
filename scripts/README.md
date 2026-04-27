# scripts

クラウド/CI/新規 Linux 環境向けセットアップスクリプト群。

## `setup_cloud_env.sh`

`flutter build apk --debug` が通る状態を作る。

### 実行

```bash
bash scripts/setup_cloud_env.sh
```

完了後は再ログインまたは `source ~/.profile` で `flutter` / `adb` / `sdkmanager` に PATH が通る。

### 何をするか

1. 外向きホストの到達性を事前チェック（Flutter 系・Android 系を分けて表示）
2. apt で `curl unzip git openjdk-17-jdk-headless` を導入（apt が無い／更新失敗してもスキップ）
3. Flutter SDK `3.41.7` を `/opt/flutter` に展開
4. `flutter pub get` を実行
5. Android command-line tools を `/opt/android-sdk/cmdline-tools/latest` に展開
6. `sdkmanager --licenses` を一括 yes
7. `platforms;android-35` `build-tools;35.0.0` `platform-tools` を導入
8. `android/local.properties` を生成（`sdk.dir` / `flutter.sdk`）
9. `~/.profile` に PATH と `ANDROID_HOME` 等を追記
10. `flutter doctor -v` で最終確認

各バージョンは環境変数で上書きできる: `FLUTTER_VERSION` / `ANDROID_PLATFORM` / `ANDROID_BUILD_TOOLS` / `CMDLINE_TOOLS_VER` / `FLUTTER_HOME` / `ANDROID_HOME`。

### 必要な外向きアクセス

| ホスト | 用途 | 必須? |
| --- | --- | --- |
| `storage.googleapis.com` | Flutter SDK アーカイブ・エンジンアーティファクト | ◎ |
| `pub.dev` | Flutter pub パッケージ | ◎ |
| `github.com` / `*.githubusercontent.com` | ソースおよびリリース成果物 | ◎ |
| `plugins.gradle.org` / `services.gradle.org` | Gradle wrapper / プラグイン | ◎ |
| `repo1.maven.org` / `repo.maven.apache.org` | Maven Central | ◎ |
| `archive.ubuntu.com` | apt（任意。導入済みなら不要） | △ |
| **`dl.google.com`** | **Android SDK バイナリ（cmdline-tools / build-tools / platform-tools / platforms）** | **★** |
| **`maven.google.com`** | **Android Gradle Plugin・AndroidX 等の公式 Maven** | **★** |

★印が遮断されている環境では Android ビルドは不可能。下記「既知の制約」を参照。

### 既知の制約 — Anthropic Claude Code 隔離サンドボックス

このリポジトリの最初の自動セットアップを行った Anthropic 標準のクラウドサンドボックスでは、エグレスゲートウェイが
`dl.google.com` と `maven.google.com` を `x-deny-reason: host_not_allowed` で遮断する。
代替パス（`storage.googleapis.com` の別バケット、Maven Central・JitPack・各社ミラー、
コンテナレジストリの blob ストレージ等）も同様に許可されておらず、サンドボックス内部からは
Android SDK と Android Gradle Plugin の取得手段が無い。

そのためサンドボックス内では `setup_cloud_env.sh` は

- Flutter SDK を `/opt/flutter` に展開
- `flutter pub get` で Dart 依存を解決

までで停止し、終了コード `2` を返す。Android ビルドを実行するには、

- 上記2ホストを許可リストに追加した別環境（社内 CI / ローカル PC など）で再実行する
- もしくは、別環境で取得した Android SDK ツリー (`$ANDROID_HOME` 配下) と
  Gradle のローカルキャッシュ (`~/.gradle/caches`) を持ち込んだ上で本スクリプトを再実行する

のいずれかが必要。
