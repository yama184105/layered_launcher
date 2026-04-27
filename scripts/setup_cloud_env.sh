#!/usr/bin/env bash
# layered_launcher : Flutter + Android SDK セットアップスクリプト
#
# 用途
#   クラウド/CI/新規 Linux 環境で `flutter build apk --debug` を実行できる
#   ようにするため、Flutter SDK と Android SDK を導入する。
#
# 必要な外向きアクセス（重要）
#   ホスト                            用途
#   ──────────────────────────────────────────────────────
#   storage.googleapis.com           Flutter SDK 本体・エンジンアーティファクト
#   pub.dev                          Flutter pub パッケージ
#   github.com / *.githubusercontent.com   ソース系
#   archive.ubuntu.com               apt パッケージ
#   plugins.gradle.org / services.gradle.org   Gradle wrapper / プラグイン
#   repo1.maven.org / repo.maven.apache.org    Maven Central
#   dl.google.com                    ★Android SDK バイナリ（必須）
#   maven.google.com                 ★Android Gradle Plugin / AndroidX（必須）
#
#   ★印のホストが社内プロキシ等で遮断されている環境では Android ビルドは不可。
#   Anthropic 標準の Claude Code 隔離サンドボックスではこの2ホストが
#   `host_not_allowed` で拒否されるため、本スクリプトは Flutter のみ導入し、
#   Android SDK のセットアップ箇所で停止する。
#
# 使い方
#   bash scripts/setup_cloud_env.sh
#
#   再ログイン後、または `source ~/.profile` で PATH を反映できる。

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.7}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
CMDLINE_TOOLS_VER="${CMDLINE_TOOLS_VER:-13114758}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-35}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-35.0.0}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

log()   { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn ]\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

check_url() {
  local url="$1"
  local code
  for _ in 1 2 3; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$url" 2>/dev/null || echo 000)
    [[ "$code" =~ ^(200|301|302|303|307|308|400|401|404|405)$ ]] && return 0
  done
  return 1
}

require_url() {
  local label="$1" url="$2"
  if check_url "$url"; then
    log "OK    : ${label}"
  else
    warn "BLOCK : ${label}"
    return 1
  fi
}

step_check_network() {
  log "外向きホスト到達性を確認"
  local missing=0
  require_url "storage.googleapis.com (Flutter SDK)" \
    "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" || missing=$((missing+1))
  require_url "pub.dev (Flutter pub)" "https://pub.dev/api/packages/flutter" || missing=$((missing+1))
  require_url "github.com" "https://github.com/" || missing=$((missing+1))
  require_url "plugins.gradle.org" "https://plugins.gradle.org/m2/" || missing=$((missing+1))
  require_url "services.gradle.org" "https://services.gradle.org/distributions/" || missing=$((missing+1))
  require_url "repo1.maven.org" "https://repo1.maven.org/maven2/" || missing=$((missing+1))
  if (( missing > 0 )); then
    fatal "Flutter のインストールに必要な基本ホストが ${missing} 件遮断されている"
  fi

  log "Android ビルド向けホストを確認"
  ANDROID_HOST_OK=1
  require_url "dl.google.com (Android SDK バイナリ)" \
    "https://dl.google.com/android/repository/repository2-3.xml" || ANDROID_HOST_OK=0
  require_url "maven.google.com (AGP/AndroidX)" \
    "https://maven.google.com/com/android/tools/build/gradle/maven-metadata.xml" || ANDROID_HOST_OK=0
}

step_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get が無い環境 — apt 段階をスキップ"
    return 0
  fi
  log "apt パッケージを導入 (curl, unzip, git, openjdk-17-jdk-headless)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null || warn "apt-get update に失敗 — 既存の環境を使う"
  apt-get install -y --no-install-recommends \
    curl unzip git ca-certificates xz-utils \
    openjdk-17-jdk-headless >/dev/null || warn "apt-get install を一部失敗 — 続行"
}

step_flutter() {
  if [[ -x "${FLUTTER_HOME}/bin/flutter" ]]; then
    log "Flutter は既に ${FLUTTER_HOME} に存在 — スキップ"
  else
    log "Flutter ${FLUTTER_VERSION} (${FLUTTER_CHANNEL}) を ${FLUTTER_HOME} に展開"
    local url="https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_CHANNEL}/linux/flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz"
    local tmp; tmp="$(mktemp -d)"
    curl -fL --retry 4 --retry-delay 2 -o "${tmp}/flutter.tar.xz" "$url"
    mkdir -p "$(dirname "${FLUTTER_HOME}")"
    tar -xf "${tmp}/flutter.tar.xz" -C "$(dirname "${FLUTTER_HOME}")"
    rm -rf "$tmp"
  fi
  git config --global --add safe.directory "${FLUTTER_HOME}"
  git config --global --add safe.directory "${PROJECT_DIR}"
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
  flutter --disable-analytics >/dev/null
  flutter --version
}

step_android_sdk() {
  if (( ANDROID_HOST_OK == 0 )); then
    warn "dl.google.com / maven.google.com が遮断されているため Android SDK は導入できない"
    warn "別環境 (ローカル PC, 社内 CI 等) で本スクリプトを実行するか、対象ホストを許可リストに追加してから再実行してほしい"
    return 1
  fi

  if [[ -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    log "Android cmdline-tools は既に存在 — スキップ"
  else
    log "Android command-line tools (${CMDLINE_TOOLS_VER}) を ${ANDROID_HOME} に展開"
    local url="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VER}_latest.zip"
    local tmp; tmp="$(mktemp -d)"
    curl -fL --retry 4 --retry-delay 2 -o "${tmp}/cmd.zip" "$url"
    mkdir -p "${ANDROID_HOME}/cmdline-tools"
    unzip -q "${tmp}/cmd.zip" -d "${ANDROID_HOME}/cmdline-tools"
    mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
    rm -rf "$tmp"
  fi

  export ANDROID_HOME ANDROID_SDK_ROOT="${ANDROID_HOME}"
  export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

  log "Android SDK パッケージを導入 (platforms;${ANDROID_PLATFORM}, build-tools;${ANDROID_BUILD_TOOLS}, platform-tools)"
  yes | sdkmanager --licenses >/dev/null
  sdkmanager \
    "platform-tools" \
    "platforms;${ANDROID_PLATFORM}" \
    "build-tools;${ANDROID_BUILD_TOOLS}"
}

step_local_properties() {
  local lp="${PROJECT_DIR}/android/local.properties"
  log "${lp} を生成"
  {
    echo "sdk.dir=${ANDROID_HOME}"
    echo "flutter.sdk=${FLUTTER_HOME}"
  } > "$lp"
}

step_profile() {
  local profile="${HOME}/.profile"
  if ! grep -q "FLUTTER_HOME=${FLUTTER_HOME}" "$profile" 2>/dev/null; then
    log "${profile} に PATH を追記"
    cat >> "$profile" <<EOF

# layered_launcher / Flutter + Android SDK
export FLUTTER_HOME="${FLUTTER_HOME}"
export ANDROID_HOME="${ANDROID_HOME}"
export ANDROID_SDK_ROOT="\${ANDROID_HOME}"
export PATH="\${FLUTTER_HOME}/bin:\${ANDROID_HOME}/cmdline-tools/latest/bin:\${ANDROID_HOME}/platform-tools:\${PATH}"
EOF
  fi
}

step_pub_get() {
  log "flutter pub get を実行"
  ( cd "${PROJECT_DIR}" && flutter pub get )
}

step_doctor() {
  log "flutter doctor で最終確認"
  flutter doctor -v || true
}

main() {
  step_check_network
  step_apt
  step_flutter
  step_pub_get

  if step_android_sdk; then
    step_local_properties
    step_profile
    step_doctor
    log "セットアップ完了 — \`flutter build apk --debug\` を実行可能"
  else
    step_profile
    warn "Flutter のみ導入済み。Android SDK 周りは上記ホストを許可してから再実行が必要"
    exit 2
  fi
}

main "$@"
