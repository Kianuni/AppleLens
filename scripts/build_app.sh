#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

VERSION="${VERSION:-1.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
UNIVERSAL="${UNIVERSAL:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

for arg in "$@"; do
    case "${arg}" in
        --universal)
            UNIVERSAL=1
            ;;
        *)
            echo "Unknown option: ${arg}" >&2
            exit 1
            ;;
    esac
done

BIN_DIR=""
if [[ "${UNIVERSAL}" == "1" ]]; then
    echo "==> Building AppleLens v${VERSION} (release universal arm64 + x86_64)..."
    if swift build -c release --arch arm64 --arch x86_64; then
        if [[ -x ".build/apple/Products/Release/AppleLensApp" && -x ".build/apple/Products/Release/applelens" ]]; then
            BIN_DIR=".build/apple/Products/Release"
        else
            BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
        fi
    else
        echo "==> Universal build unavailable on this toolchain; falling back to native arch..."
        UNIVERSAL=0
    fi
fi

if [[ "${UNIVERSAL}" != "1" ]]; then
    echo "==> Building AppleLens v${VERSION} (release native arch)..."
    swift build -c release
    BIN_DIR=".build/release"
    if [[ ! -x "${BIN_DIR}/AppleLensApp" || ! -x "${BIN_DIR}/applelens" ]]; then
        BIN_DIR="$(swift build -c release --show-bin-path)"
    fi
fi

APP_DIR="dist/AppleLens.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Assembling ${APP_DIR} and dist/applelens..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_DIR}/AppleLensApp" "${MACOS_DIR}/AppleLens"
cp "${BIN_DIR}/applelens" "${MACOS_DIR}/applelens-cli"
cp "${BIN_DIR}/applelens" "dist/applelens"
chmod +x "${MACOS_DIR}/AppleLens" "${MACOS_DIR}/applelens-cli" "dist/applelens"

if [[ ! -f "${MACOS_DIR}/AppleLens" || ! -f "${MACOS_DIR}/applelens-cli" ]] || cmp -s "${MACOS_DIR}/AppleLens" "${MACOS_DIR}/applelens-cli"; then
    echo "Error: GUI binary (AppleLens) and CLI binary (applelens-cli) must be distinct files!" >&2
    exit 1
fi

echo "==> Generating AppIcon.icns..."
swift scripts/generate_icon.swift "${RESOURCES_DIR}/AppIcon.icns"

echo "==> Writing Info.plist (v${VERSION}, build ${BUILD_NUMBER})..."
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>AppleLens</string>
    <key>CFBundleExecutable</key>
    <string>AppleLens</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.kianuni.AppleLens</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AppleLens</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Apple Intelligence Report</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>json</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.json</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

if [[ -n "${CODESIGN_IDENTITY}" ]]; then
    echo "==> Code signing ${APP_DIR} with Developer ID (${CODESIGN_IDENTITY})..."
    codesign --force --options runtime --timestamp -s "${CODESIGN_IDENTITY}" "${MACOS_DIR}/applelens-cli"
    codesign --force --options runtime --timestamp -s "${CODESIGN_IDENTITY}" "${MACOS_DIR}/AppleLens"
    codesign --force --deep --options runtime --timestamp -s "${CODESIGN_IDENTITY}" "${APP_DIR}"
else
    echo "==> Ad-hoc code signing ${APP_DIR}..."
    codesign --force -s - "${MACOS_DIR}/applelens-cli"
    codesign --force -s - "${MACOS_DIR}/AppleLens"
    codesign --force --deep -s - "${APP_DIR}"
fi

codesign --verify --deep --strict "${APP_DIR}"

ARCH_INFO="$(lipo -archs "${MACOS_DIR}/AppleLens" 2>/dev/null || uname -m)"
echo "==> Build complete:"
echo "    Version    : v${VERSION} (${BUILD_NUMBER})"
echo "    Archs      : ${ARCH_INFO}"
echo "    App Bundle : ${REPO_ROOT}/${APP_DIR}"
echo "    CLI Binary : ${REPO_ROOT}/${MACOS_DIR}/applelens-cli"
echo "    App Icon   : ${REPO_ROOT}/${RESOURCES_DIR}/AppIcon.icns"
