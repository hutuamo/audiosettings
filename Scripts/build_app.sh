#!/usr/bin/env bash

set -euo pipefail

APP_NAME="AudioSettings"
APP_VERSION="2026.1"
BUNDLE_ID="com.local.AudioSettings"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_PATH="${ROOT_DIR}/Assets/AppIcon/AudioSettings.icns"

cd "${ROOT_DIR}"

# 使用 SwiftPM 生成 release 可执行文件。
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/${APP_NAME}"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "未找到可执行文件：${EXECUTABLE_PATH}" >&2
  exit 1
fi

if [[ ! -f "${ICON_PATH}" ]]; then
  echo "未找到 App 图标：${ICON_PATH}" >&2
  exit 1
fi

rm -rf "${APP_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${ICON_PATH}" "${RESOURCES_DIR}/${APP_NAME}.icns"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key>
  <string>${APP_NAME}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>用于实时显示所选输入设备的电平，以验证麦克风能否正常拾音。仅在本机内存中计算电平，不录音、不保存、不上传。</string>
</dict>
</plist>
PLIST

# 本地 ad-hoc 签名，便于 macOS 以标准 App 包形式启动。
codesign --force --sign - "${APP_PATH}" >/dev/null

echo "已生成：${APP_PATH}"
echo "启动命令：open \"${APP_PATH}\""
