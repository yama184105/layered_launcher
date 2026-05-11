#!/usr/bin/env bash
set -e
set -x

# =========================================
# Flutter SDK
# =========================================
FLUTTER_VERSION=3.41.7

if [ ! -d /opt/flutter ]; then
  echo "Downloading Flutter ${FLUTTER_VERSION}..."
  curl -fL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz
  mkdir -p /opt
  tar xf /tmp/flutter.tar.xz -C /opt
  rm /tmp/flutter.tar.xz
fi

chown -R root:root /opt/flutter || true
git config --global --add safe.directory '*'

export PATH="/opt/flutter/bin:$PATH"
grep -q "flutter/bin" /root/.bashrc 2>/dev/null || \
  echo 'export PATH="/opt/flutter/bin:$PATH"' >> /root/.bashrc
echo 'export PATH="/opt/flutter/bin:$PATH"' > /etc/profile.d/flutter.sh
chmod +x /etc/profile.d/flutter.sh
ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter
ln -sf /opt/flutter/bin/dart /usr/local/bin/dart

flutter --version
flutter precache
flutter config --no-analytics

# =========================================
# Android SDK
# =========================================
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_HOME=$ANDROID_SDK_ROOT

if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]; then
  echo "Downloading Android command-line tools..."
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  curl -fL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdtools.zip
  unzip -q /tmp/cmdtools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm /tmp/cmdtools.zip
fi

export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

yes | sdkmanager --licenses > /dev/null || true
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

{
  echo "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
  echo "export ANDROID_HOME=$ANDROID_SDK_ROOT"
  echo 'export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"'
} >> /root/.bashrc

{
  echo "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
  echo "export ANDROID_HOME=$ANDROID_SDK_ROOT"
  echo 'export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"'
} >> /etc/profile.d/flutter.sh

ln -sf "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" /usr/local/bin/sdkmanager
ln -sf "$ANDROID_SDK_ROOT/platform-tools/adb" /usr/local/bin/adb 2>/dev/null || true

flutter config --android-sdk "$ANDROID_SDK_ROOT"

# =========================================
# Project deps
# =========================================
cd "$(git rev-parse --show-toplevel)"
flutter pub get || true

flutter doctor -v || true
