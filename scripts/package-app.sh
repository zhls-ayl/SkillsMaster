#!/bin/bash
# package-app.sh — Build macOS .app bundles and release artifacts for SkillsMaster.
#
# Features:
#   1. Build universal / arm64 / x86_64 release binaries using swift build
#   2. Assemble standard .app bundle directory structure
#   3. Generate Info.plist (including version metadata)
#   4. Copy icon and SPM resource bundle
#   5. Optionally create zip and dmg artifacts
#   6. Optionally produce the full release asset matrix in one run
#
# Usage:
#   ./scripts/package-app.sh --version 1.0.0
#   ./scripts/package-app.sh --version 1.0.0 --zip
#   ./scripts/package-app.sh --version 1.0.0 --arch arm64 --zip
#   ./scripts/package-app.sh --version 1.0.0 --release-assets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}" 2>/dev/null || echo "0.0.0")"
CREATE_ZIP="false"
CREATE_DMG="false"
RELEASE_ASSETS="false"
OUTPUT_DIR="build"
APP_NAME="SkillsMaster"
TARGET_ARCH="universal"
TEMP_DIRS=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --version X.Y.Z        Set CFBundleShortVersionString / CFBundleVersion (default: ${VERSION})
  --arch ARCH            Build target: universal | arm64 | x86_64 (default: ${TARGET_ARCH})
  --zip                  Also create a zip archive for the selected arch
  --dmg                  Also create a dmg for the selected arch (only supported for universal)
  --release-assets       Create the full release matrix:
                         ${APP_NAME}-v<version>-universal.zip
                         ${APP_NAME}-v<version>-arm64.zip
                         ${APP_NAME}-v<version>-x86_64.zip
                         ${APP_NAME}-v<version>-universal.dmg
  --output-dir DIR       Output directory for .app and archives (default: ${OUTPUT_DIR})
  -h, --help             Show this help
EOF
}

cleanup() {
    local dir
    for dir in "${TEMP_DIRS[@]:-}"; do
        if [ -n "$dir" ] && [ -d "$dir" ]; then
            rm -rf "$dir"
        fi
    done
}

trap cleanup EXIT

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

create_temp_dir() {
    local __resultvar="$1"
    local dir
    dir="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.XXXXXX")"
    TEMP_DIRS+=("$dir")
    printf -v "$__resultvar" '%s' "$dir"
}

archive_suffix_for_arch() {
    case "$1" in
        universal) echo "universal" ;;
        arm64) echo "arm64" ;;
        x86_64) echo "x86_64" ;;
        *)
            echo "Error: Unsupported arch label '$1'" >&2
            exit 1
            ;;
    esac
}

app_output_path_for_arch() {
    local arch="$1"
    if [ "$arch" = "universal" ]; then
        echo "${OUTPUT_DIR}/${APP_NAME}.app"
    else
        echo "${OUTPUT_DIR}/${APP_NAME}-${arch}.app"
    fi
}

zip_output_path_for_arch() {
    local suffix
    suffix="$(archive_suffix_for_arch "$1")"
    echo "${OUTPUT_DIR}/${APP_NAME}-v${VERSION}-${suffix}.zip"
}

dmg_output_path_for_arch() {
    local suffix
    suffix="$(archive_suffix_for_arch "$1")"
    echo "${OUTPUT_DIR}/${APP_NAME}-v${VERSION}-${suffix}.dmg"
}

absolute_path() {
    local path="$1"
    if [[ "$path" = /* ]]; then
        echo "$path"
    else
        echo "${PROJECT_ROOT}/${path}"
    fi
}

write_info_plist() {
    local plist_path="$1"
    cat > "$plist_path" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.github.skillsmaster</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST_EOF
}

verify_binary_arch() {
    local binary_path="$1"
    local arch="$2"
    local arch_info
    arch_info="$(file "$binary_path")"

    echo "==> Binary found: ${binary_path}"
    echo "    ${arch_info#*: }"

    case "$arch" in
        universal)
            if [[ "$arch_info" != *"arm64"* || "$arch_info" != *"x86_64"* ]]; then
                echo "Error: Expected a universal binary containing both arm64 and x86_64."
                exit 1
            fi
            ;;
        arm64)
            if [[ "$arch_info" != *"arm64"* || "$arch_info" == *"x86_64"* ]]; then
                echo "Error: Expected an arm64-only binary."
                exit 1
            fi
            ;;
        x86_64)
            if [[ "$arch_info" != *"x86_64"* || "$arch_info" == *"arm64"* ]]; then
                echo "Error: Expected an x86_64-only binary."
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown arch '${arch}'"
            exit 1
            ;;
    esac
}

find_build_binary() {
    local scratch_path="$1"
    local binary_path
    binary_path="$(find "$scratch_path" -type f \( -path "*/Release/${APP_NAME}" -o -path "*/release/${APP_NAME}" \) | head -n 1)"
    if [ -z "$binary_path" ]; then
        echo "Error: Binary not found after build under ${scratch_path}."
        exit 1
    fi
    echo "$binary_path"
}

find_resource_bundle() {
    local scratch_path="$1"
    local resource_bundle
    resource_bundle="$(find "$scratch_path" -type d -name "${APP_NAME}_${APP_NAME}.bundle" | head -n 1)"
    echo "$resource_bundle"
}

assemble_app_bundle() {
    local binary_path="$1"
    local resource_bundle="$2"
    local bundle_path="$3"
    local arch="$4"

    local contents_dir="${bundle_path}/Contents"
    local macos_dir="${contents_dir}/MacOS"
    local resources_dir="${contents_dir}/Resources"

    rm -rf "$bundle_path"
    mkdir -p "$macos_dir" "$resources_dir"

    cp "$binary_path" "${macos_dir}/${APP_NAME}"
    chmod +x "${macos_dir}/${APP_NAME}"

    local icon_source="Sources/SkillsMaster/Resources/AppIcon.icns"
    if [ -f "$icon_source" ]; then
        cp "$icon_source" "${resources_dir}/AppIcon.icns"
    else
        echo "Warning: AppIcon.icns not found at ${icon_source}"
    fi

    if [ -n "$resource_bundle" ] && [ -d "$resource_bundle" ]; then
        if [ "$arch" = "universal" ]; then
            cp -R "$resource_bundle" "$resources_dir/"
        else
            # Single-arch `swift build` emits a resource accessor that looks for
            # `SkillsMaster_SkillsMaster.bundle` next to `SkillsMaster.app`.
            cp -R "$resource_bundle" "$bundle_path/"
        fi
    else
        echo "Warning: SPM resource bundle not found. App may miss bundled assets."
    fi

    write_info_plist "${contents_dir}/Info.plist"
}

build_bundle_for_arch() {
    local __resultvar="$1"
    local arch="$2"
    local scratch_path="$3"
    local stage_root="$4"

    mkdir -p "$scratch_path"

    local -a swift_args=(build -c release --scratch-path "$scratch_path")
    case "$arch" in
        universal)
            swift_args+=(--arch arm64 --arch x86_64)
            echo "==> Building ${APP_NAME} v${VERSION} (universal: arm64 + x86_64) ..."
            ;;
        arm64|x86_64)
            swift_args+=(--arch "$arch")
            echo "==> Building ${APP_NAME} v${VERSION} (${arch}) ..."
            ;;
        *)
            echo "Error: Unsupported arch '${arch}'"
            exit 1
            ;;
    esac

    swift "${swift_args[@]}"

    local binary_path
    binary_path="$(find_build_binary "$scratch_path")"
    verify_binary_arch "$binary_path" "$arch"

    local resource_bundle
    resource_bundle="$(find_resource_bundle "$scratch_path")"

    local app_bundle_path="${stage_root}/SkillsMaster.app"
    assemble_app_bundle "$binary_path" "$resource_bundle" "$app_bundle_path" "$arch"
    printf -v "$__resultvar" '%s' "$app_bundle_path"
}

copy_bundle_to_output() {
    local bundle_path="$1"
    local destination="$2"

    rm -rf "$destination"
    cp -R "$bundle_path" "$destination"
}

create_zip_from_bundle() {
    local bundle_path="$1"
    local zip_path="$2"
    local absolute_zip_path
    absolute_zip_path="$(absolute_path "$zip_path")"

    mkdir -p "$(dirname "$absolute_zip_path")"
    rm -f "$absolute_zip_path"
    (
        cd "$(dirname "$bundle_path")"
        ditto -c -k --keepParent "$(basename "$bundle_path")" "$(basename "$absolute_zip_path")"
        mv "$(basename "$absolute_zip_path")" "$absolute_zip_path"
    )
}

create_dmg_from_bundle() {
    local bundle_path="$1"
    local dmg_path="$2"
    local dmg_stage
    create_temp_dir dmg_stage
    local absolute_dmg_path
    absolute_dmg_path="$(absolute_path "$dmg_path")"

    cp -R "$bundle_path" "${dmg_stage}/${APP_NAME}.app"
    ln -s /Applications "${dmg_stage}/Applications"

    mkdir -p "$(dirname "$absolute_dmg_path")"
    rm -f "$absolute_dmg_path"
    hdiutil create \
        -volname "${APP_NAME}" \
        -srcfolder "$dmg_stage" \
        -ov \
        -format UDZO \
        "$absolute_dmg_path" >/dev/null
}

package_single_arch() {
    local arch="$1"
    local scratch_path="${PROJECT_ROOT}/.build/package-${arch}"
    local stage_root
    create_temp_dir stage_root

    local bundle_path
    build_bundle_for_arch bundle_path "$arch" "$scratch_path" "$stage_root"

    local app_output
    app_output="$(app_output_path_for_arch "$arch")"
    copy_bundle_to_output "$bundle_path" "$app_output"

    if [ "$CREATE_ZIP" = "true" ]; then
        local zip_output
        zip_output="$(zip_output_path_for_arch "$arch")"
        echo "==> Creating zip archive: $(basename "$zip_output")"
        create_zip_from_bundle "$bundle_path" "$zip_output"
    fi

    if [ "$CREATE_DMG" = "true" ]; then
        if [ "$arch" != "universal" ]; then
            echo "Error: --dmg is only supported together with --arch universal."
            exit 1
        fi
        local dmg_output
        dmg_output="$(dmg_output_path_for_arch "$arch")"
        echo "==> Creating dmg archive: $(basename "$dmg_output")"
        create_dmg_from_bundle "$bundle_path" "$dmg_output"
    fi

    echo ""
    echo "==> Done! App bundle created at: ${app_output}"
    echo "    Size: $(du -sh "$app_output" | cut -f1)"
    if [ "$CREATE_ZIP" = "true" ]; then
        local zip_output
        zip_output="$(zip_output_path_for_arch "$arch")"
        echo "==> Zip archive created at: ${zip_output}"
        echo "    Size: $(du -sh "$zip_output" | cut -f1)"
    fi
    if [ "$CREATE_DMG" = "true" ]; then
        local dmg_output
        dmg_output="$(dmg_output_path_for_arch "$arch")"
        echo "==> DMG archive created at: ${dmg_output}"
        echo "    Size: $(du -sh "$dmg_output" | cut -f1)"
    fi
}

package_release_assets() {
    mkdir -p "$OUTPUT_DIR"

    local universal_stage arm64_stage x86_stage
    create_temp_dir universal_stage
    create_temp_dir arm64_stage
    create_temp_dir x86_stage

    local universal_bundle arm64_bundle x86_bundle
    build_bundle_for_arch universal_bundle "universal" "${PROJECT_ROOT}/.build/package-universal" "$universal_stage"
    build_bundle_for_arch arm64_bundle "arm64" "${PROJECT_ROOT}/.build/package-arm64" "$arm64_stage"
    build_bundle_for_arch x86_bundle "x86_64" "${PROJECT_ROOT}/.build/package-x86_64" "$x86_stage"

    copy_bundle_to_output "$universal_bundle" "${OUTPUT_DIR}/${APP_NAME}.app"

    echo "==> Creating release asset archives ..."
    create_zip_from_bundle "$universal_bundle" "$(zip_output_path_for_arch "universal")"
    create_zip_from_bundle "$arm64_bundle" "$(zip_output_path_for_arch "arm64")"
    create_zip_from_bundle "$x86_bundle" "$(zip_output_path_for_arch "x86_64")"
    create_dmg_from_bundle "$universal_bundle" "$(dmg_output_path_for_arch "universal")"

    echo ""
    echo "==> Release assets created:"
    echo "    ${OUTPUT_DIR}/${APP_NAME}.app"
    echo "    $(zip_output_path_for_arch "universal")"
    echo "    $(zip_output_path_for_arch "arm64")"
    echo "    $(zip_output_path_for_arch "x86_64")"
    echo "    $(dmg_output_path_for_arch "universal")"
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
        --arch)
            if [[ $# -lt 2 ]]; then
                echo "Error: --arch requires a value"
                usage
                exit 1
            fi
            TARGET_ARCH="$2"
            shift 2
            ;;
        --zip)
            CREATE_ZIP="true"
            shift
            ;;
        --dmg)
            CREATE_DMG="true"
            shift
            ;;
        --release-assets)
            RELEASE_ASSETS="true"
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

case "$TARGET_ARCH" in
    universal|arm64|x86_64) ;;
    *)
        echo "Error: Invalid arch '${TARGET_ARCH}'. Expected universal, arm64, or x86_64."
        exit 1
        ;;
esac

if [ "$RELEASE_ASSETS" = "true" ] && { [ "$CREATE_ZIP" = "true" ] || [ "$CREATE_DMG" = "true" ] || [ "$TARGET_ARCH" != "universal" ]; }; then
    echo "Error: --release-assets cannot be combined with --zip, --dmg, or a non-universal --arch."
    exit 1
fi

if [ "$CREATE_DMG" = "true" ] && [ "$TARGET_ARCH" != "universal" ]; then
    echo "Error: --dmg is only supported together with --arch universal."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

mkdir -p "$OUTPUT_DIR"

require_cmd swift
require_cmd file
require_cmd otool
require_cmd xcode-select
check_xcode_tools

if [ "$CREATE_ZIP" = "true" ] || [ "$RELEASE_ASSETS" = "true" ]; then
    require_cmd ditto
fi

if [ "$CREATE_DMG" = "true" ] || [ "$RELEASE_ASSETS" = "true" ]; then
    require_cmd hdiutil
fi

if [ "$RELEASE_ASSETS" = "true" ]; then
    package_release_assets
else
    package_single_arch "$TARGET_ARCH"
fi

echo ""
echo "To launch:"
echo "    open $(app_output_path_for_arch "$TARGET_ARCH")"
