#!/bin/bash
# package-app.sh — Build universal binary and assemble macOS .app bundle.
#
# Features:
#   1. Compile arm64 + x86_64 universal binary using swift build
#   2. Create standard .app bundle directory structure
#   3. Generate Info.plist (including version metadata)
#   4. Copy icon and SPM resource bundle
#   5. Optionally create a distributable zip archive
#
# Usage:
#   ./scripts/package-app.sh
#   ./scripts/package-app.sh --version 1.0.0
#   ./scripts/package-app.sh --version 1.0.0 --zip

set -euo pipefail

VERSION="0.0.0"
CREATE_ZIP="false"
OUTPUT_DIR="build"
APP_NAME="SkillsMaster"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --version X.Y.Z     Set CFBundleShortVersionString / CFBundleVersion (default: ${VERSION})
  --zip               Also create zip archive: <output-dir>/${APP_NAME}-v<version>-universal.zip
  --output-dir DIR    Output directory for .app and .zip (default: ${OUTPUT_DIR})
  -h, --help          Show this help
EOF
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command not found: ${cmd}"
        exit 1
    fi
}

check_xcode_tools() {
    local dev_dir
    dev_dir="$(xcode-select -p 2>/dev/null || true)"
    if [ -z "$dev_dir" ]; then
        echo "Error: Xcode developer directory is not configured."
        echo "Fix:"
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi

    local actool_path="${dev_dir}/usr/bin/actool"
    if [ ! -x "$actool_path" ]; then
        echo "Error: actool not found at: ${actool_path}"
        echo "Fix:"
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        exit 1
    fi

    if ! "$actool_path" --version >/dev/null 2>&1; then
        echo "Error: actool is present but failed to initialize."
        echo "Common fix steps:"
        echo "  sudo xcodebuild -license accept"
        echo "  sudo xcodebuild -runFirstLaunch"
        echo "  open /Applications/Xcode.app   # wait until components installation completes"
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            if [[ $# -lt 2 ]]; then
                echo "Error: --version requires a value"
                usage
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        --zip)
            CREATE_ZIP="true"
            shift
            ;;
        --output-dir)
            if [[ $# -lt 2 ]]; then
                echo "Error: --output-dir requires a value"
                usage
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid version '${VERSION}'. Expected X.Y.Z (e.g. 1.2.3)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

require_cmd swift
require_cmd file
require_cmd xcode-select
check_xcode_tools
if [ "$CREATE_ZIP" = "true" ]; then
    require_cmd ditto
fi

echo "==> Building ${APP_NAME} v${VERSION}"
echo "==> Building universal binary (arm64 + x86_64) ..."
swift build -c release --arch arm64 --arch x86_64

# Universal output usually lives under .build/apple/Products/Release.
# Keep a fallback for environments that still place output under .build/release.
BINARY_PATH=".build/apple/Products/Release/${APP_NAME}"
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH=".build/release/${APP_NAME}"
fi
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found after build."
    echo "Checked:"
    echo "  .build/apple/Products/Release/${APP_NAME}"
    echo "  .build/release/${APP_NAME}"
    exit 1
fi

ARCH_INFO="$(file "$BINARY_PATH")"
echo "==> Binary found: ${BINARY_PATH}"
echo "    ${ARCH_INFO#*: }"

if [[ "$ARCH_INFO" != *"arm64"* || "$ARCH_INFO" != *"x86_64"* ]]; then
    echo "Error: Expected a universal binary containing both arm64 and x86_64."
    exit 1
fi

# SPM packages resources as <Target>_<Target>.bundle.
RESOURCE_BUNDLE=""
for candidate in \
    ".build/apple/Products/Release/${APP_NAME}_${APP_NAME}.bundle" \
    ".build/release/${APP_NAME}_${APP_NAME}.bundle"; do
    if [ -d "$candidate" ]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done

if [ -z "$RESOURCE_BUNDLE" ]; then
    echo "Warning: SPM resource bundle not found. App may miss bundled assets."
fi

APP_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> Assembling .app bundle ..."
cp "$BINARY_PATH" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

ICON_SOURCE="Sources/SkillsMaster/Resources/AppIcon.icns"
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "${RESOURCES_DIR}/AppIcon.icns"
    echo "    Copied AppIcon.icns"
else
    echo "Warning: AppIcon.icns not found at ${ICON_SOURCE}"
fi

if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    echo "    Copied SPM resource bundle"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Unique Identifier, similar to Android package name -->
    <key>CFBundleIdentifier</key>
    <string>com.github.skillsmaster</string>

    <!-- App Display Name -->
    <key>CFBundleName</key>
    <string>SkillsMaster</string>

    <!-- Executable Filename (matches filename in MacOS/ directory) -->
    <key>CFBundleExecutable</key>
    <string>SkillsMaster</string>

    <!-- User-visible Version Number (e.g. 1.0.0) -->
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <!-- Internal Build Version Number (here same as user version) -->
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <!-- App Icon Filename (without .icns extension) -->
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <!-- Bundle Type: APPL indicates this is an application -->
    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <!-- Info.plist Format Version -->
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <!-- Minimum Supported macOS Version -->
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <!-- Support High Resolution Retina Display -->
    <key>NSHighResolutionCapable</key>
    <true/>

    <!-- App Category: Developer Tools -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST_EOF

echo "    Generated Info.plist (version: ${VERSION})"

ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}-v${VERSION}-universal.zip"
if [ "$CREATE_ZIP" = "true" ]; then
    echo "==> Creating zip archive ..."
    mkdir -p "$OUTPUT_DIR"
    (
        cd "$OUTPUT_DIR"
        ditto -c -k --keepParent "${APP_NAME}.app" "$(basename "$ZIP_PATH")"
    )
fi

echo ""
echo "==> Done! App bundle created at: $APP_DIR"
echo "    Size: $(du -sh "$APP_DIR" | cut -f1)"
if [ "$CREATE_ZIP" = "true" ]; then
    echo "==> Zip archive created at: $ZIP_PATH"
    echo "    Size: $(du -sh "$ZIP_PATH" | cut -f1)"
fi
echo ""
echo "To launch:"
echo "    open $APP_DIR"
echo ""
echo "To verify architecture:"
echo "    file $MACOS_DIR/$APP_NAME"
