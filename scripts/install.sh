#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-Kianuni/AppleLens}"
TARGET_APP="/Applications/AppleLens.app"
FORCE_LOCAL=0

for arg in "$@"; do
    case "${arg}" in
        --local)
            FORCE_LOCAL=1
            ;;
        --help|-h)
            echo "Usage: $0 [--local]"
            echo "  --local   Install from local ./dist/AppleLens.app or ./dist/AppleLens.dmg instead of GitHub Releases."
            exit 0
            ;;
        *)
            echo "Error: Unknown option '${arg}'. Usage: $0 [--local]" >&2
            exit 1
            ;;
    esac
done

TMP_DIR="$(mktemp -d)"
MOUNT_POINT=""
cleanup() {
    if [[ -n "${MOUNT_POINT}" ]]; then
        hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
    fi
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

LOCAL_DIST=""
if [[ -d "./dist" ]]; then
    LOCAL_DIST="./dist"
elif [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != /dev/fd/* && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "${SCRIPT_DIR}/../dist" ]]; then
        LOCAL_DIST="${SCRIPT_DIR}/../dist"
    fi
fi

LOCAL_APP=""
LOCAL_DMG=""
if [[ -n "${LOCAL_DIST}" ]]; then
    if [[ -d "${LOCAL_DIST}/AppleLens.app" ]]; then
        LOCAL_APP="${LOCAL_DIST}/AppleLens.app"
    fi
    if [[ -f "${LOCAL_DIST}/AppleLens.dmg" ]]; then
        LOCAL_DMG="${LOCAL_DIST}/AppleLens.dmg"
    else
        for candidate in "${LOCAL_DIST}"/AppleLens-v*-universal.dmg; do
            if [[ -f "${candidate}" ]]; then
                LOCAL_DMG="${candidate}"
                break
            fi
        done
    fi
fi

SOURCE_APP=""
if [[ -n "${LOCAL_APP}" ]]; then
    echo "==> Installing AppleLens from local ${LOCAL_APP}..."
    SOURCE_APP="${LOCAL_APP}"
elif [[ -n "${LOCAL_DMG}" ]]; then
    echo "==> Mounting local DMG ${LOCAL_DMG}..."
    MOUNT_POINT="${TMP_DIR}/dmg_mount"
    mkdir -p "${MOUNT_POINT}"
    hdiutil attach "${LOCAL_DMG}" -nobrowse -readonly -mountpoint "${MOUNT_POINT}" >/dev/null
    SOURCE_APP="${MOUNT_POINT}/AppleLens.app"
elif [[ "${FORCE_LOCAL}" == "1" ]]; then
    echo "Error: --local specified, but neither ./dist/AppleLens.app nor ./dist/AppleLens.dmg was found." >&2
    echo "Run ./scripts/build_app.sh or ./scripts/package_release.sh first." >&2
    exit 1
else
    echo "==> Fetching latest AppleLens release from https://github.com/${REPO}/releases/latest ..."
    API_URL="https://api.github.com/repos/${REPO}/releases/latest"
    RELEASE_JSON="$(curl -fsSL "${API_URL}")"

    ASSET_URL="$(printf '%s\n' "${RELEASE_JSON}" | grep -Eo '"browser_download_url": *"[^"]*macos-universal\.zip"' | head -n 1 | cut -d '"' -f 4 || true)"
    if [[ -z "${ASSET_URL}" ]]; then
        echo "Error: Could not find a macos-universal.zip release asset for ${REPO}." >&2
        exit 1
    fi

    SHA_URL="$(printf '%s\n' "${RELEASE_JSON}" | grep -Eo '"browser_download_url": *"[^"]*SHA256SUMS\.txt"' | head -n 1 | cut -d '"' -f 4 || true)"
    if [[ -z "${SHA_URL}" ]]; then
        echo "Error: Latest release for ${REPO} is missing SHA256SUMS.txt; aborting installation before extraction." >&2
        exit 1
    fi

    ZIP_BASENAME="$(basename "${ASSET_URL}")"
    ZIP_BASENAME="${ZIP_BASENAME%%\?*}"
    ZIP_FILE="${TMP_DIR}/${ZIP_BASENAME}"
    SHA_FILE="${TMP_DIR}/SHA256SUMS.txt"

    echo "==> Downloading ${ZIP_BASENAME} and SHA256SUMS.txt..."
    curl -fL "${ASSET_URL}" -o "${ZIP_FILE}"
    if ! curl -fsSL "${SHA_URL}" -o "${SHA_FILE}" || [[ ! -s "${SHA_FILE}" ]]; then
        echo "Error: Failed to download SHA256SUMS.txt from ${SHA_URL}; aborting before extraction." >&2
        exit 1
    fi

    EXPECTED_SHA="$(awk -v target="${ZIP_BASENAME}" '
        {
            gsub(/\r$/, "", $0)
            file = $2
            sub(/^\*/, "", file)
            sub(/^\.\//, "", file)
            if (file == target && $1 ~ /^[0-9a-fA-F]{64}$/) {
                print tolower($1)
                exit
            }
        }
    ' "${SHA_FILE}")"

    if [[ -z "${EXPECTED_SHA}" ]]; then
        echo "Error: SHA256SUMS.txt does not list a valid SHA-256 checksum for ${ZIP_BASENAME}; aborting before extraction." >&2
        exit 1
    fi

    ACTUAL_SHA="$(shasum -a 256 "${ZIP_FILE}" | awk '{print tolower($1)}')"
    if [[ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]]; then
        echo "Error: SHA-256 checksum mismatch for ${ZIP_BASENAME}!" >&2
        echo "  Expected: ${EXPECTED_SHA}" >&2
        echo "  Actual  : ${ACTUAL_SHA}" >&2
        echo "Aborting installation before extraction or quarantine removal." >&2
        exit 1
    fi

    echo "==> SHA-256 verified for ${ZIP_BASENAME}: ${ACTUAL_SHA}"
    ditto -xk "${ZIP_FILE}" "${TMP_DIR}/extracted"
    SOURCE_APP="${TMP_DIR}/extracted/AppleLens.app"
fi

if [[ ! -d "${SOURCE_APP}" ]]; then
    echo "Error: AppleLens.app not found at ${SOURCE_APP}" >&2
    exit 1
fi

killall AppleLens 2>/dev/null || true
rm -rf "${TARGET_APP}"
cp -R "${SOURCE_APP}" "${TARGET_APP}"

echo "==> Clearing Gatekeeper quarantine attribute..."
xattr -cr "${TARGET_APP}" 2>/dev/null || true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${TARGET_APP}" || true
fi

echo "==> AppleLens installed successfully!"
echo "    App Bundle : ${TARGET_APP}"
echo "    CLI Binary : ${TARGET_APP}/Contents/MacOS/applelens-cli"
echo "    Optional CLI symlink: sudo ln -sf ${TARGET_APP}/Contents/MacOS/applelens-cli /usr/local/bin/applelens"
