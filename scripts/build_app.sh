#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WhereAmIP"
BUNDLE_ID="com.whereamip.app"
VERSION="${VERSION:-1.0.0}"
DIST_DIR="dist"
BUILD_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_STAGING="${DIST_DIR}/dmg_staging"
DMG_PATH="${DIST_DIR}/${APP_NAME}-v${VERSION}.dmg"
CODESIGN_ID="${CODESIGN_IDENTITY:--}"

echo "🔨 [1/4] 正在编译 Release 版本 (支持 Apple Silicon + Intel 通用二进制)..."
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_PATH=".build/apple/Products/Release/${APP_NAME}"
    echo "   ✅ 已生成通用二进制 (Universal Binary: arm64 + x86_64)"
else
    swift build -c release
    BIN_PATH=".build/release/${APP_NAME}"
    echo "   ✅ 已生成当前架构 Release 二进制"
fi

echo "📦 [2/4] 正在组装 macOS 应用程序包 (${BUILD_DIR})..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${BUILD_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${BUILD_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${BUILD_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
EOF

echo "🔏 [3/4] 正在对 ${APP_NAME}.app 执行 Ad-hoc 本地代码签名..."
codesign --force --deep --sign "${CODESIGN_ID}" "${BUILD_DIR}"

echo "💿 [4/4] 正在生成 DMG 拖拽安装镜像 (${DMG_PATH})..."
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
cp -R "${BUILD_DIR}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${DMG_STAGING}"

echo ""
echo "🎉 构建与打包完成！产出物列表："
echo "   1. 应用本体 : ${BUILD_DIR}"
echo "   2. DMG 镜像 : ${DMG_PATH}"
