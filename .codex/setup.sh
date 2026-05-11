#!/usr/bin/env bash
# layered_launcher : Codex environment bootstrap
#
# Reproduces the Flutter/Android/Linux/Web toolchain used by this repository.
# Intended for Ubuntu/Debian based Codex or CI containers.

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter-${FLUTTER_VERSION}}"
FLUTTER_SYMLINK="${FLUTTER_SYMLINK:-/opt/flutter}"
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
CMDLINE_TOOLS_VER="${CMDLINE_TOOLS_VER:-13114758}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"
ANDROID_PLATFORMS=("android-35" "android-36")
ANDROID_BUILD_TOOLS=("35.0.0" "36.0.0")
JAVA_HOME="${SETUP_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()   { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn ]\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  fatal "root ではなく sudo も無いため、/opt や apt パッケージを更新できません"
fi

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
  require_url "dl.google.com (Android SDK / Chrome)" \
    "https://dl.google.com/android/repository/repository2-3.xml" || missing=$((missing+1))
  require_url "maven.google.com (AGP/AndroidX)" \
    "https://maven.google.com/com/android/tools/build/gradle/maven-metadata.xml" || missing=$((missing+1))
  if (( missing > 0 )); then
    fatal "セットアップに必要な外向きホストが ${missing} 件遮断されています"
  fi
}

step_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get が無い環境 — apt 段階をスキップ"
    return 0
  fi

  log "apt パッケージを導入 (OpenJDK 17, Linux desktop build libs, Chrome prerequisites)"
  export DEBIAN_FRONTEND=noninteractive
  "${SUDO[@]}" apt-get update -y
  "${SUDO[@]}" apt-get install -y --no-install-recommends \
    ca-certificates \
    clang \
    cmake \
    curl \
    git \
    gnupg \
    libblkid-dev \
    libgtk-3-dev \
    liblzma-dev \
    ninja-build \
    openjdk-17-jdk-headless \
    pkg-config \
    unzip \
    wget \
    xz-utils
}

step_chrome() {
  if command -v google-chrome >/dev/null 2>&1; then
    log "Google Chrome は既に存在 — スキップ"
    google-chrome --version || true
    return 0
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get が無いため Google Chrome の導入をスキップ"
    return 0
  fi

  log "Google Chrome を Web 検証用に導入"
  local keyring="/usr/share/keyrings/google-linux-signing-keyring.gpg"
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | "${SUDO[@]}" gpg --dearmor -o "${keyring}"
  echo "deb [arch=amd64 signed-by=${keyring}] http://dl.google.com/linux/chrome/deb/ stable main" \
    | "${SUDO[@]}" tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
  "${SUDO[@]}" apt-get update -y
  "${SUDO[@]}" apt-get install -y --no-install-recommends google-chrome-stable
  google-chrome --version || true
}

step_flutter() {
  if [[ -x "${FLUTTER_HOME}/bin/flutter" ]]; then
    log "Flutter ${FLUTTER_VERSION} は既に ${FLUTTER_HOME} に存在 — スキップ"
  else
    log "Flutter ${FLUTTER_VERSION} (${FLUTTER_CHANNEL}) を ${FLUTTER_HOME} に展開"
    local url="https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_CHANNEL}/linux/flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz"
    local tmp; tmp="$(mktemp -d)"
    curl -fL --retry 4 --retry-delay 2 -o "${tmp}/flutter.tar.xz" "$url"
    tar -xf "${tmp}/flutter.tar.xz" -C "${tmp}"
    "${SUDO[@]}" mkdir -p "$(dirname "${FLUTTER_HOME}")"
    "${SUDO[@]}" rm -rf "${FLUTTER_HOME}"
    "${SUDO[@]}" mv "${tmp}/flutter" "${FLUTTER_HOME}"
    rm -rf "$tmp"
  fi

  "${SUDO[@]}" ln -sfn "${FLUTTER_HOME}" "${FLUTTER_SYMLINK}"
  git config --global --add safe.directory "${FLUTTER_HOME}" || true
  git config --global --add safe.directory "${FLUTTER_SYMLINK}" || true
  git config --global --add safe.directory "${PROJECT_DIR}" || true

  export PATH="${FLUTTER_HOME}/bin:${PATH}"
  flutter --disable-analytics >/dev/null
  flutter --version
}

step_android_sdk() {
  if [[ -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    log "Android cmdline-tools は既に存在 — スキップ"
  else
    log "Android command-line tools (${CMDLINE_TOOLS_VER}) を ${ANDROID_HOME} に展開"
    local url="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VER}_latest.zip"
    local tmp; tmp="$(mktemp -d)"
    curl -fL --retry 4 --retry-delay 2 -o "${tmp}/cmd.zip" "$url"
    "${SUDO[@]}" mkdir -p "${ANDROID_HOME}/cmdline-tools"
    unzip -q "${tmp}/cmd.zip" -d "${tmp}"
    "${SUDO[@]}" rm -rf "${ANDROID_HOME}/cmdline-tools/latest"
    "${SUDO[@]}" mv "${tmp}/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
    rm -rf "$tmp"
  fi

  export ANDROID_HOME ANDROID_SDK_ROOT="${ANDROID_HOME}"
  export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

  local packages=("platform-tools" "ndk;${ANDROID_NDK_VERSION}")
  local platform build_tools
  for platform in "${ANDROID_PLATFORMS[@]}"; do
    packages+=("platforms;${platform}")
  done
  for build_tools in "${ANDROID_BUILD_TOOLS[@]}"; do
    packages+=("build-tools;${build_tools}")
  done

  log "Android SDK パッケージを導入 (${packages[*]})"
  set +o pipefail
  yes | sdkmanager --licenses >/dev/null
  local license_status=$?
  set -o pipefail
  if (( license_status != 0 )); then
    fatal "Android SDK ライセンスの受諾に失敗しました"
  fi
  sdkmanager "${packages[@]}"

  "${SUDO[@]}" ln -sfn "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" /usr/local/bin/sdkmanager
  "${SUDO[@]}" ln -sfn "${ANDROID_HOME}/platform-tools/adb" /usr/local/bin/adb
}

step_flutter_android_config() {
  log "Flutter の Android/JDK 設定を更新"
  export JAVA_HOME
  flutter config --android-sdk "${ANDROID_HOME}" >/dev/null
  flutter config --jdk-dir "${JAVA_HOME}" >/dev/null
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
  touch "$profile"
  if ! grep -q "layered_launcher / Flutter + Android SDK" "$profile" 2>/dev/null; then
    log "${profile} に PATH を追記"
    cat >> "$profile" <<EOF_PROFILE

# layered_launcher / Flutter + Android SDK
export FLUTTER_HOME="${FLUTTER_HOME}"
export ANDROID_HOME="${ANDROID_HOME}"
export ANDROID_SDK_ROOT="\${ANDROID_HOME}"
export JAVA_HOME="${JAVA_HOME}"
export PATH="\${FLUTTER_HOME}/bin:\${ANDROID_HOME}/cmdline-tools/latest/bin:\${ANDROID_HOME}/platform-tools:\${PATH}"
EOF_PROFILE
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
  step_chrome
  step_flutter
  step_android_sdk
  step_flutter_android_config
  step_local_properties
  step_profile
  step_pub_get
  step_doctor
  log "セットアップ完了 — flutter build apk --debug / flutter run -d chrome / Linux desktop build を実行可能"
}

main "$@"
