#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

VERSION="${VERSION:-1.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
export VERSION BUILD_NUMBER

VERSION="${VERSION}" BUILD_NUMBER="${BUILD_NUMBER}" "${SCRIPT_DIR}/build_app.sh" --universal

STAGE_DMG="$(mktemp -d)"
STAGE_PKG="$(mktemp -d)"
cleanup() {
    rm -rf "${STAGE_DMG}" "${STAGE_PKG}"
}
trap cleanup EXIT

DMG_VERSIONED="dist/AppleLens-v${VERSION}-universal.dmg"
DMG_LATEST="dist/AppleLens.dmg"
ZIP_PATH="dist/AppleLens-v${VERSION}-macos-universal.zip"
PKG_PATH="dist/AppleLens-v${VERSION}-installer.pkg"

echo "==> Preparing drag-and-drop DMG staging..."
cp -R "dist/AppleLens.app" "${STAGE_DMG}/AppleLens.app"
ln -s /Applications "${STAGE_DMG}/Applications"

cat > "${STAGE_DMG}/首次打开说明 (ReadMe).txt" <<'EOF'
AppleLens 安装与首次打开说明 (macOS 14.0+)
=================================================

1. 将 AppleLens.app 拖拽到右侧「Applications (应用程序)」文件夹。
2. 首次运行说明（Gatekeeper 隔离处理）：
   若本镜像通过浏览器下载且未经过付费 Developer ID 公证，首次双击可能提示
   “无法验证开发者”。请任选以下一种方式放行：
   - 方法 A（推荐，一行终端命令）：
     xattr -cr /Applications/AppleLens.app
   - 方法 B（图形界面）：
     在弹窗点「取消 / 好」，前往「系统设置 -> 隐私与安全性」底部点击「仍要打开」。
3. 可选开启全局命令行 `applelens`：
   sudo ln -sf /Applications/AppleLens.app/Contents/MacOS/applelens-cli /usr/local/bin/applelens

-------------------------------------------------

AppleLens Installation & First-Launch Guide
=================================================

1. Drag AppleLens.app into the Applications shortcut.
2. If Gatekeeper blocks first launch on ad-hoc signed builds downloaded via a browser:
   - Run in Terminal:
     xattr -cr /Applications/AppleLens.app
   - Or go to System Settings -> Privacy & Security -> Open Anyway.
3. Optional CLI symlink:
   sudo ln -sf /Applications/AppleLens.app/Contents/MacOS/applelens-cli /usr/local/bin/applelens
EOF

echo "==> Creating ${DMG_VERSIONED}..."
rm -f "${DMG_VERSIONED}" "${DMG_LATEST}"
hdiutil create \
    -volname "AppleLens" \
    -srcfolder "${STAGE_DMG}" \
    -ov \
    -format UDZO \
    "${DMG_VERSIONED}"
cp "${DMG_VERSIONED}" "${DMG_LATEST}"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    echo "==> Notarizing ${DMG_VERSIONED}..."
    xcrun notarytool submit "${DMG_VERSIONED}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_PASSWORD}" \
        --wait
    xcrun stapler staple "${DMG_VERSIONED}"
    cp "${DMG_VERSIONED}" "${DMG_LATEST}"
fi

echo "==> Creating ${ZIP_PATH}..."
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "dist/AppleLens.app" "${ZIP_PATH}"

echo "==> Creating ${PKG_PATH}..."
mkdir -p "${STAGE_PKG}/Applications" "${STAGE_PKG}/usr/local/bin"
cp -R "dist/AppleLens.app" "${STAGE_PKG}/Applications/AppleLens.app"
ln -sf /Applications/AppleLens.app/Contents/MacOS/applelens-cli "${STAGE_PKG}/usr/local/bin/applelens"
rm -f "${PKG_PATH}"
pkgbuild \
    --root "${STAGE_PKG}" \
    --identifier "com.kianuni.AppleLens.pkg" \
    --version "${VERSION}" \
    --install-location "/" \
    "${PKG_PATH}"

echo "==> Generating dist/SHA256SUMS.txt..."
(
    cd dist
    shasum -a 256 \
        "AppleLens-v${VERSION}-universal.dmg" \
        "AppleLens-v${VERSION}-macos-universal.zip" \
        "AppleLens-v${VERSION}-installer.pkg" > SHA256SUMS.txt
)

CASK_PATH="Casks/applelens.rb"
if [[ -f "${CASK_PATH}" ]]; then
    DMG_SHA256="$(awk -v target="AppleLens-v${VERSION}-universal.dmg" '
        {
            gsub(/\r$/, "", $0)
            file = $2
            sub(/^\*/, "", file)
            if (file == target && $1 ~ /^[0-9a-fA-F]{64}$/) {
                print tolower($1)
                exit
            }
        }
    ' dist/SHA256SUMS.txt)"
    if [[ -z "${DMG_SHA256}" ]]; then
        echo "Error: Failed to extract SHA-256 for AppleLens-v${VERSION}-universal.dmg from dist/SHA256SUMS.txt" >&2
        exit 1
    fi
    echo "==> Updating ${CASK_PATH} (version ${VERSION}, sha256 ${DMG_SHA256})..."
    CASK_TMP="$(mktemp)"
    awk -v ver="${VERSION}" -v sha="${DMG_SHA256}" '
        /^[[:space:]]*version[[:space:]]+"[^"]*"/ {
            sub(/"[^"]*"/, "\"" ver "\"")
        }
        /^[[:space:]]*sha256[[:space:]]+"[^"]*"/ {
            sub(/"[^"]*"/, "\"" sha "\"")
        }
        { print }
    ' "${CASK_PATH}" > "${CASK_TMP}"
    mv "${CASK_TMP}" "${CASK_PATH}"
fi

echo "==> Release packages ready:"
ls -lh "${DMG_VERSIONED}" "${DMG_LATEST}" "${ZIP_PATH}" "${PKG_PATH}" "dist/SHA256SUMS.txt" "${CASK_PATH}"
