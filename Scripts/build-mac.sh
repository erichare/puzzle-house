#!/bin/bash
# Build, archive, and (optionally) upload the native macOS Puzzle House app to
# the Mac App Store (TestFlight). Mirror of build-ios.sh for the PuzzleHouseMac
# scheme.
#
# Usage:
#   Scripts/build-mac.sh archive   # archive only, no upload
#   Scripts/build-mac.sh upload    # archive + export .pkg + upload to ASC
#
# Required env when uploading (or archiving with manual signing):
#   AC_API_KEY_ID       — ASC API key id (10-char)
#   AC_API_ISSUER_ID    — issuer UUID
#   AC_API_KEY_P8_PATH  — path to .p8 private key
#                         OR AC_API_KEY_P8_BASE64 with its base64 (or PEM)
#   TEAM_ID             — 10-char Apple Developer team id
#
# macOS App Store uploads need TWO signing identities in the keychain:
#   • "Apple Distribution"               — signs the .app (unified cert, the
#                                          same one iOS uses)
#   • "3rd Party Mac Developer Installer" — signs the .pkg installer
#   Override the installer identity via MAC_INSTALLER_IDENTITY if your cert is
#   named differently.
#
# Bundle ids default to project.yml; override via env if you renamed:
#   MAC_APP_BUNDLE_ID                — com.jestats.PuzzleHouse
#   MAC_SHARE_EXTENSION_BUNDLE_ID    — com.jestats.PuzzleHouse.MacShareExtension
#   MAC_WIDGET_BUNDLE_ID             — com.jestats.PuzzleHouse.MacWidget

set -euo pipefail

MODE="${1:-archive}"
SCHEME="PuzzleHouseMac"
PROJECT="PuzzleHouse.xcodeproj"
BUILD_DIR="${BUILD_DIR:-build-mac}"
ARCHIVE_PATH="${BUILD_DIR}/PuzzleHouseMac.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MAC_APP_BUNDLE_ID="${MAC_APP_BUNDLE_ID:-com.jestats.PuzzleHouse}"
MAC_SHARE_EXTENSION_BUNDLE_ID="${MAC_SHARE_EXTENSION_BUNDLE_ID:-com.jestats.PuzzleHouse.MacShareExtension}"
MAC_WIDGET_BUNDLE_ID="${MAC_WIDGET_BUNDLE_ID:-com.jestats.PuzzleHouse.MacWidget}"
MAC_INSTALLER_IDENTITY="${MAC_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer}"
export MAC_APP_BUNDLE_ID MAC_SHARE_EXTENSION_BUNDLE_ID MAC_WIDGET_BUNDLE_ID

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is required (brew install xcodegen)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the ASC API key once so both `archive` and `upload` modes can pass it
# to xcodebuild for cert / profile fetch, and so the upload step can stage it
# where `altool` expects.
AC_AUTH_FLAGS=()
AC_KEY_TMPDIR=""
if [[ -n "${AC_API_KEY_P8_BASE64:-}" ]]; then
    AC_KEY_TMPDIR=$(mktemp -d)
    export AC_API_KEY_P8_PATH="${AC_KEY_TMPDIR}/AuthKey_${AC_API_KEY_ID}.p8"
    if printf '%s' "${AC_API_KEY_P8_BASE64}" | head -n 1 | grep -q '^-----BEGIN'; then
        printf '%s\n' "${AC_API_KEY_P8_BASE64}" > "${AC_API_KEY_P8_PATH}"
    else
        printf '%s' "${AC_API_KEY_P8_BASE64}" | base64 -D > "${AC_API_KEY_P8_PATH}"
    fi
    trap 'rm -rf "${AC_KEY_TMPDIR}"' EXIT
fi
[[ -n "${AC_API_KEY_ID:-}" ]] && export AC_API_KEY_ID
[[ -n "${AC_API_ISSUER_ID:-}" ]] && export AC_API_ISSUER_ID
[[ -n "${AC_API_KEY_P8_PATH:-}" ]] && export AC_API_KEY_P8_PATH
if [[ -n "${AC_API_KEY_ID:-}" && -n "${AC_API_ISSUER_ID:-}" && -n "${AC_API_KEY_P8_PATH:-}" ]]; then
    AC_AUTH_FLAGS=(
        "-authenticationKeyID" "${AC_API_KEY_ID}"
        "-authenticationKeyIssuerID" "${AC_API_ISSUER_ID}"
        "-authenticationKeyPath" "${AC_API_KEY_P8_PATH}"
    )
    echo "==> Using ASC API key ${AC_API_KEY_ID} for signing"
else
    echo "==> No ASC API key in env — falling back to Xcode's signed-in Apple ID"
fi

# ---------------------------------------------------------------------------
echo "==> Regenerating Xcode project from spec"
( cd "${REPO_ROOT}" && xcodegen generate )

mkdir -p "${BUILD_DIR}"

# Pin App Store profiles to the local Apple Distribution cert's serial so a
# stale ASC profile attached to an old/revoked cert doesn't get picked.
if command -v security >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
    CERT_PEM="$(mktemp -t puzzle-house-dist-cert.XXXXXX)"
    if security find-certificate -c "Apple Distribution" -p > "${CERT_PEM}" 2>/dev/null; then
        CERT_SERIAL="$(
            openssl x509 -in "${CERT_PEM}" -noout -serial 2>/dev/null \
                | sed 's/^serial=//' \
                | tr '[:lower:]' '[:upper:]' \
                | tr -d ':'
        )"
        if [[ -n "${CERT_SERIAL}" ]]; then
            export ASC_CERT_SERIAL_NUMBER="${CERT_SERIAL}"
            echo "==> Pinning App Store profiles to Apple Distribution cert serial ${ASC_CERT_SERIAL_NUMBER}"
        fi
    fi
    rm -f "${CERT_PEM}"
fi

# ---------------------------------------------------------------------------
# Pre-create the three Mac App Store profiles (app + share ext + widget). Each
# call to asc_ensure_profile.py is idempotent.
APP_PROFILE_NAME=""
APP_PROFILE_UUID=""
SHARE_PROFILE_NAME=""
SHARE_PROFILE_UUID=""
WIDGET_PROFILE_NAME=""
WIDGET_PROFILE_UUID=""
if [[ -n "${AC_API_KEY_ID:-}" && -n "${AC_API_KEY_P8_PATH:-}" ]]; then
    ensure_profile() {
        env PLATFORM="$1" python3 "${REPO_ROOT}/Scripts/asc_ensure_profile.py"
    }

    echo "==> Ensuring profile (mac app)"
    out="$(ensure_profile MAC_APP)"
    APP_PROFILE_NAME="$(printf '%s\n' "${out}" | sed -n '1p')"
    APP_PROFILE_UUID="$(printf '%s\n' "${out}" | sed -n '3p')"

    echo "==> Ensuring profile (mac share extension)"
    out="$(ensure_profile MAC_SHARE_EXTENSION)"
    SHARE_PROFILE_NAME="$(printf '%s\n' "${out}" | sed -n '1p')"
    SHARE_PROFILE_UUID="$(printf '%s\n' "${out}" | sed -n '3p')"

    echo "==> Ensuring profile (mac widget)"
    out="$(ensure_profile MAC_WIDGET)"
    WIDGET_PROFILE_NAME="$(printf '%s\n' "${out}" | sed -n '1p')"
    WIDGET_PROFILE_UUID="$(printf '%s\n' "${out}" | sed -n '3p')"
fi

# ---------------------------------------------------------------------------
SIGN_BUILD_SETTINGS=()
if [[ -n "${APP_PROFILE_NAME}" ]]; then
    SIGN_BUILD_SETTINGS=(
        "CODE_SIGN_STYLE=Manual"
        "CODE_SIGN_IDENTITY=Apple Distribution"
        "DEVELOPMENT_TEAM=${TEAM_ID:-}"
        "PUZZLE_HOUSE_MAC_APP_PROFILE_NAME=${APP_PROFILE_NAME}"
        "PUZZLE_HOUSE_MAC_APP_PROFILE_UUID=${APP_PROFILE_UUID}"
        "PUZZLE_HOUSE_MAC_SHARE_EXTENSION_PROFILE_NAME=${SHARE_PROFILE_NAME}"
        "PUZZLE_HOUSE_MAC_SHARE_EXTENSION_PROFILE_UUID=${SHARE_PROFILE_UUID}"
        "PUZZLE_HOUSE_MAC_WIDGET_PROFILE_NAME=${WIDGET_PROFILE_NAME}"
        "PUZZLE_HOUSE_MAC_WIDGET_PROFILE_UUID=${WIDGET_PROFILE_UUID}"
    )
else
    SIGN_BUILD_SETTINGS=("CODE_SIGN_IDENTITY=Apple Distribution")
fi

XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR="${XCODE_DEVELOPER_DIR}"
XCODEBUILD="${XCODE_DEVELOPER_DIR}/usr/bin/xcodebuild"

echo "==> Archiving for macOS"
"${XCODEBUILD}" \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -sdk macosx \
    -destination 'generic/platform=macOS' \
    -archivePath "${ARCHIVE_PATH}" \
    -allowProvisioningUpdates \
    ${AC_AUTH_FLAGS[@]+"${AC_AUTH_FLAGS[@]}"} \
    "${SIGN_BUILD_SETTINGS[@]}" \
    archive

if [[ "${MODE}" == "archive" ]]; then
    echo "==> Archive ready: ${ARCHIVE_PATH}"
    echo "    Open Xcode → Window → Organizer → Distribute App to upload."
    exit 0
fi

# ---------------------------------------------------------------------------
echo "==> Writing ExportOptions.plist"
EXPORT_APP_PROFILE="${APP_PROFILE_UUID:-${APP_PROFILE_NAME:-Puzzle House Mac App Store}}"
EXPORT_SHARE_PROFILE="${SHARE_PROFILE_UUID:-${SHARE_PROFILE_NAME:-Puzzle House Mac Share Extension App Store}}"
EXPORT_WIDGET_PROFILE="${WIDGET_PROFILE_UUID:-${WIDGET_PROFILE_NAME:-Puzzle House Mac Widget App Store}}"

cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>teamID</key>
    <string>${TEAM_ID:-}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
    <key>installerSigningCertificate</key>
    <string>${MAC_INSTALLER_IDENTITY}</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>${MAC_APP_BUNDLE_ID}</key>
        <string>${EXPORT_APP_PROFILE}</string>
        <key>${MAC_SHARE_EXTENSION_BUNDLE_ID}</key>
        <string>${EXPORT_SHARE_PROFILE}</string>
        <key>${MAC_WIDGET_BUNDLE_ID}</key>
        <string>${EXPORT_WIDGET_PROFILE}</string>
    </dict>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Exporting .pkg"
"${XCODEBUILD}" \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -allowProvisioningUpdates \
    ${AC_AUTH_FLAGS[@]+"${AC_AUTH_FLAGS[@]}"}

PKG=$(find "${EXPORT_DIR}" -maxdepth 1 -name '*.pkg' | head -n 1)
if [[ -z "${PKG}" ]]; then
    echo "error: no .pkg produced under ${EXPORT_DIR}" >&2
    exit 1
fi
echo "==> Exported: ${PKG}"

if [[ -z "${AC_API_KEY_ID:-}" || -z "${AC_API_ISSUER_ID:-}" || -z "${AC_API_KEY_P8_PATH:-}" ]]; then
    echo "error: set AC_API_KEY_ID, AC_API_ISSUER_ID, and AC_API_KEY_P8_BASE64 to upload" >&2
    exit 1
fi

# `xcrun altool` ignores --apiKeyPath; stage the key where it looks.
ALTOOL_KEY_DIR="${HOME}/.appstoreconnect/private_keys"
mkdir -p "${ALTOOL_KEY_DIR}"
ALTOOL_KEY_PATH="${ALTOOL_KEY_DIR}/AuthKey_${AC_API_KEY_ID}.p8"
cp "${AC_API_KEY_P8_PATH}" "${ALTOOL_KEY_PATH}"
chmod 600 "${ALTOOL_KEY_PATH}"
trap 'rm -f "${ALTOOL_KEY_PATH}"; rm -rf "${AC_KEY_TMPDIR}"' EXIT

echo "==> Uploading to App Store Connect (TestFlight)"
set +e
ALTOOL_OUTPUT=$(xcrun altool \
    --upload-app \
    --type macos \
    --file "${PKG}" \
    --apiKey "${AC_API_KEY_ID}" \
    --apiIssuer "${AC_API_ISSUER_ID}" 2>&1)
ALTOOL_RC=$?
set -e
printf '%s\n' "${ALTOOL_OUTPUT}"
if [[ ${ALTOOL_RC} -ne 0 ]] || \
   printf '%s\n' "${ALTOOL_OUTPUT}" | grep -Eq 'UPLOAD FAILED|Validation failed|Failed to upload package|STATE_ERROR'; then
    echo "error: App Store Connect upload failed" >&2
    exit 1
fi

echo "==> Upload complete. TestFlight processing typically takes 10-30 minutes."
echo "    Track progress at: https://appstoreconnect.apple.com/apps"
