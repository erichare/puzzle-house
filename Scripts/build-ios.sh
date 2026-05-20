#!/bin/bash
# Build, archive, and (optionally) upload Puzzle House to TestFlight.
#
# Usage:
#   Scripts/build-ios.sh archive   # archive only, no upload
#   Scripts/build-ios.sh upload    # archive + export IPA + upload to ASC
#
# Required env when uploading (or archiving with manual signing):
#   AC_API_KEY_ID       — ASC API key id (10-char)
#   AC_API_ISSUER_ID    — issuer UUID
#   AC_API_KEY_P8_PATH  — path to .p8 private key
#                         OR AC_API_KEY_P8_BASE64 with its base64 (or PEM)
#                         contents
#   TEAM_ID             — 10-char Apple Developer team id
#
# Bundle ids defaults match project.yml; override via env if you renamed:
#   IOS_APP_BUNDLE_ID                — com.jestats.PuzzleHouse
#   IOS_SHARE_EXTENSION_BUNDLE_ID    — com.jestats.PuzzleHouse.ShareExtension
#   IOS_MESSAGES_BUNDLE_ID           — com.jestats.PuzzleHouse.Messages
#   IOS_WIDGET_BUNDLE_ID             — com.jestats.PuzzleHouse.Widget

set -euo pipefail

MODE="${1:-archive}"
SCHEME="PuzzleHouse"
PROJECT="PuzzleHouse.xcodeproj"
BUILD_DIR="${BUILD_DIR:-build-ios}"
ARCHIVE_PATH="${BUILD_DIR}/PuzzleHouse.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

IOS_APP_BUNDLE_ID="${IOS_APP_BUNDLE_ID:-com.jestats.PuzzleHouse}"
IOS_SHARE_EXTENSION_BUNDLE_ID="${IOS_SHARE_EXTENSION_BUNDLE_ID:-com.jestats.PuzzleHouse.ShareExtension}"
IOS_MESSAGES_BUNDLE_ID="${IOS_MESSAGES_BUNDLE_ID:-com.jestats.PuzzleHouse.Messages}"
IOS_WIDGET_BUNDLE_ID="${IOS_WIDGET_BUNDLE_ID:-com.jestats.PuzzleHouse.Widget}"
export IOS_APP_BUNDLE_ID IOS_SHARE_EXTENSION_BUNDLE_ID
export IOS_MESSAGES_BUNDLE_ID IOS_WIDGET_BUNDLE_ID

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is required (brew install xcodegen)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the ASC API key once so both `archive` and `upload` modes can pass
# it to xcodebuild for cert / profile fetch, and so the upload step can
# stage it where `altool` expects.
AC_AUTH_FLAGS=()
AC_KEY_TMPDIR=""
if [[ -n "${AC_API_KEY_P8_BASE64:-}" ]]; then
    AC_KEY_TMPDIR=$(mktemp -d)
    export AC_API_KEY_P8_PATH="${AC_KEY_TMPDIR}/AuthKey_${AC_API_KEY_ID}.p8"
    # Accept either raw PEM or base64-encoded PEM in the secret; auto-detect.
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
# Pre-create all four App Store profiles (main + 3 extensions). Each call to
# `asc_ensure_profile.py` is idempotent: if the profile already exists it's
# downloaded + installed; otherwise it's created via the ASC API.
APP_PROFILE_NAME=""
APP_PROFILE_UUID=""
SHARE_PROFILE_NAME=""
SHARE_PROFILE_UUID=""
MESSAGES_PROFILE_NAME=""
MESSAGES_PROFILE_UUID=""
WIDGET_PROFILE_NAME=""
WIDGET_PROFILE_UUID=""
if [[ -n "${AC_API_KEY_ID:-}" && -n "${AC_API_KEY_P8_PATH:-}" ]]; then
    ensure_profile() {
        local platform="$1"
        local out
        env PLATFORM="${platform}" python3 "${REPO_ROOT}/Scripts/asc_ensure_profile.py"
    }

    echo "==> Ensuring profile (main app)"
    out="$(ensure_profile IOS_APP)"
    APP_PROFILE_NAME="$(printf '%s\n' "${out}" | sed -n '1p')"
    APP_PROFILE_UUID="$(printf '%s\n' "${out}" | sed -n '3p')"

    echo "==> Ensuring profile (share extension)"
    out="$(ensure_profile IOS_SHARE_EXTENSION)"
    SHARE_PROFILE_NAME="$(printf '%s\n' "${out}" | sed -n '1p')"
    SHARE_PROFILE_UUID="$(printf '%s\n' "${out}" | sed -n '3p')"

    echo "==> Ensuring profile (messages extension)"
    out="$(ensure_profile IOS_MESSAGES)"
    MESSAGES_PROFILE_NAME="$(printf '%s\n' "${out}" | sed -n '1p')"
    MESSAGES_PROFILE_UUID="$(printf '%s\n' "${out}" | sed -n '3p')"

    echo "==> Ensuring profile (widget)"
    out="$(ensure_profile IOS_WIDGET)"
    WIDGET_PROFILE_NAME="$(printf '%s\n' "${out}" | sed -n '1p')"
    WIDGET_PROFILE_UUID="$(printf '%s\n' "${out}" | sed -n '3p')"
fi

# ---------------------------------------------------------------------------
# Archive. With manual signing + explicit profile specifiers, xcodebuild can't
# fall back to Automatic and pick the wrong profile type.
SIGN_BUILD_SETTINGS=()
if [[ -n "${APP_PROFILE_NAME}" ]]; then
    SIGN_BUILD_SETTINGS=(
        "CODE_SIGN_STYLE=Manual"
        "CODE_SIGN_IDENTITY=Apple Distribution"
        "DEVELOPMENT_TEAM=${TEAM_ID:-}"
        "PUZZLE_HOUSE_APP_PROFILE_NAME=${APP_PROFILE_NAME}"
        "PUZZLE_HOUSE_APP_PROFILE_UUID=${APP_PROFILE_UUID}"
        "PUZZLE_HOUSE_SHARE_EXTENSION_PROFILE_NAME=${SHARE_PROFILE_NAME}"
        "PUZZLE_HOUSE_SHARE_EXTENSION_PROFILE_UUID=${SHARE_PROFILE_UUID}"
        "PUZZLE_HOUSE_MESSAGES_PROFILE_NAME=${MESSAGES_PROFILE_NAME}"
        "PUZZLE_HOUSE_MESSAGES_PROFILE_UUID=${MESSAGES_PROFILE_UUID}"
        "PUZZLE_HOUSE_WIDGET_PROFILE_NAME=${WIDGET_PROFILE_NAME}"
        "PUZZLE_HOUSE_WIDGET_PROFILE_UUID=${WIDGET_PROFILE_UUID}"
    )
else
    SIGN_BUILD_SETTINGS=("CODE_SIGN_IDENTITY=Apple Distribution")
fi

# Use an absolute path to xcodebuild so PATH/Xcode-beta confusion can't
# resolve us to the wrong toolchain (see reolens build-ios.sh for the long
# history). DEVELOPER_DIR is set by the workflow before calling this script.
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR="${XCODE_DEVELOPER_DIR}"
XCODEBUILD="${XCODE_DEVELOPER_DIR}/usr/bin/xcodebuild"

echo "==> Archiving for iphoneos"
"${XCODEBUILD}" \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
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
EXPORT_APP_PROFILE="${APP_PROFILE_UUID:-${APP_PROFILE_NAME:-Puzzle House iOS App Store}}"
EXPORT_SHARE_PROFILE="${SHARE_PROFILE_UUID:-${SHARE_PROFILE_NAME:-Puzzle House Share Extension App Store}}"
EXPORT_MESSAGES_PROFILE="${MESSAGES_PROFILE_UUID:-${MESSAGES_PROFILE_NAME:-Puzzle House Messages App Store}}"
EXPORT_WIDGET_PROFILE="${WIDGET_PROFILE_UUID:-${WIDGET_PROFILE_NAME:-Puzzle House Widget App Store}}"

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
    <key>provisioningProfiles</key>
    <dict>
        <key>${IOS_APP_BUNDLE_ID}</key>
        <string>${EXPORT_APP_PROFILE}</string>
        <key>${IOS_SHARE_EXTENSION_BUNDLE_ID}</key>
        <string>${EXPORT_SHARE_PROFILE}</string>
        <key>${IOS_MESSAGES_BUNDLE_ID}</key>
        <string>${EXPORT_MESSAGES_PROFILE}</string>
        <key>${IOS_WIDGET_BUNDLE_ID}</key>
        <string>${EXPORT_WIDGET_PROFILE}</string>
    </dict>
    <key>uploadSymbols</key>
    <true/>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Exporting .ipa"
"${XCODEBUILD}" \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -allowProvisioningUpdates \
    ${AC_AUTH_FLAGS[@]+"${AC_AUTH_FLAGS[@]}"}

IPA=$(find "${EXPORT_DIR}" -maxdepth 1 -name '*.ipa' | head -n 1)
if [[ -z "${IPA}" ]]; then
    echo "error: no .ipa produced under ${EXPORT_DIR}" >&2
    exit 1
fi
echo "==> Exported: ${IPA}"

if [[ -z "${AC_API_KEY_ID:-}" || -z "${AC_API_ISSUER_ID:-}" || -z "${AC_API_KEY_P8_PATH:-}" ]]; then
    echo "error: set AC_API_KEY_ID, AC_API_ISSUER_ID, and AC_API_KEY_P8_BASE64 to upload" >&2
    exit 1
fi

# `xcrun altool` ignores --apiKeyPath; it only looks at fixed locations.
# Stage the key into the canonical ~/.appstoreconnect/private_keys path.
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
    --type ios \
    --file "${IPA}" \
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
