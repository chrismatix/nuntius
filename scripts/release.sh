#!/bin/bash
#
# Nuntius Release Script
# Builds, signs, notarizes, and packages Nuntius.app into a DMG.
#
# Prerequisites:
#   - Xcode Command Line Tools
#   - Developer ID Application certificate in keychain
#   - App-specific password for notarization stored in keychain:
#       xcrun notarytool store-credentials "nuntius-notary" \
#         --apple-id "your@email.com" \
#         --team-id "YOUR_TEAM_ID" \
#         --password "app-specific-password"
#
# Usage:
#   ./scripts/release.sh [--skip-notarize]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
APP_NAME="Nuntius"
# Configurable via environment
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-nuntius-notary}"
BUILD_DIR="${PROJECT_ROOT}/.build/release-bundle"
DMG_DIR="${PROJECT_ROOT}/.build/dmg"

SKIP_NOTARIZE=false
SKIP_SIGN=false
RELEASE_VERSION=""

usage() {
  echo "Usage: $0 [--skip-notarize] [--skip-sign] [--version X.Y.Z]"
  echo ""
  echo "Options:"
  echo "  --skip-notarize  Skip notarization (for local testing)"
  echo "  --skip-sign      Skip code signing (for sharing with friends)"
  echo "  --version        Create git tag and GitHub release (requires gh)"
  exit 1
}

main() {
  parse_args "$@"

  echo "==> Building ${APP_NAME} for release..."
  build_app

  echo "==> Creating app bundle..."
  create_bundle

  if [[ "${SKIP_SIGN}" == "false" ]]; then
    echo "==> Signing app bundle..."
    sign_app
  else
    echo "==> Skipping code signing (--skip-sign)"
  fi

  if [[ "${SKIP_NOTARIZE}" == "false" ]]; then
    echo "==> Creating DMG for notarization..."
    create_dmg

    echo "==> Notarizing DMG..."
    notarize_dmg

    echo "==> Stapling notarization ticket..."
    staple_dmg
  else
    echo "==> Skipping notarization"
    echo "==> Creating DMG..."
    create_dmg
  fi

  echo ""
  echo "==> Release complete!"
  echo "    DMG: ${DMG_DIR}/${APP_NAME}.dmg"

  if [[ -n "${RELEASE_VERSION}" ]]; then
    create_git_tag_and_release
  fi

  if [[ "${SKIP_SIGN}" == "true" ]]; then
    echo ""
    echo "    NOTE: This is an unsigned build. Recipients should run:"
    echo "    xattr -cr /Applications/${APP_NAME}.app"
    echo "    Or right-click the app and select 'Open' to bypass Gatekeeper."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-notarize)
        SKIP_NOTARIZE=true
        shift
        ;;
      --skip-sign)
        SKIP_SIGN=true
        SKIP_NOTARIZE=true  # Can't notarize without signing
        shift
        ;;
      --version)
        if [[ -z "${2:-}" ]]; then
          echo "Missing version after --version" >&2
          usage
        fi
        RELEASE_VERSION="$2"
        shift 2
        ;;
      -h|--help)
        usage
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        ;;
    esac
  done
}

build_app() {
  cd "${PROJECT_ROOT}"
  swift build -c release
}

create_bundle() {
  local app_bundle="${BUILD_DIR}/${APP_NAME}.app"
  local contents="${app_bundle}/Contents"
  local macos="${contents}/MacOS"
  local resources="${contents}/Resources"
  local frameworks="${contents}/Frameworks"

  rm -rf "${BUILD_DIR}"
  mkdir -p "${macos}" "${resources}" "${frameworks}"

  # Copy executable
  cp "${PROJECT_ROOT}/.build/release/Nuntius" "${macos}/${APP_NAME}"

  # Copy Info.plist
  cp "${PROJECT_ROOT}/Info.plist" "${contents}/Info.plist"

  # Copy resources from the build (SwiftPM bundles assets here)
  local bundle_resources="${PROJECT_ROOT}/.build/release/Nuntius_Nuntius.bundle"
  if [[ -d "${bundle_resources}" ]]; then
    cp -R "${bundle_resources}/"* "${resources}/"
  fi

  # Copy Assets.xcassets icons directly (actool compile)
  compile_assets "${resources}"

  echo "    Bundle created at: ${app_bundle}"
}

compile_assets() {
  local resources_dir="$1"
  local assets_path="${PROJECT_ROOT}/Sources/Nuntius/Assets.xcassets"

  if [[ -d "${assets_path}" ]]; then
    xcrun actool "${assets_path}" \
      --compile "${resources_dir}" \
      --platform macosx \
      --minimum-deployment-target 14.0 \
      --app-icon AppIcon \
      --output-partial-info-plist "${BUILD_DIR}/AssetInfo.plist" \
      2>/dev/null || true
  fi
}

sign_app() {
  local app_bundle="${BUILD_DIR}/${APP_NAME}.app"
  local entitlements="${PROJECT_ROOT}/Nuntius.entitlements"

  # Sign the main executable
  codesign --force --options runtime \
    --entitlements "${entitlements}" \
    --sign "${SIGNING_IDENTITY}" \
    "${app_bundle}/Contents/MacOS/${APP_NAME}"

  # Sign the app bundle
  codesign --force --options runtime \
    --entitlements "${entitlements}" \
    --sign "${SIGNING_IDENTITY}" \
    "${app_bundle}"

  # Verify signature
  codesign --verify --deep --strict --verbose=2 "${app_bundle}"
  echo "    Signature verified"
}

create_dmg() {
  local app_bundle="${BUILD_DIR}/${APP_NAME}.app"
  local dmg_path="${DMG_DIR}/${APP_NAME}.dmg"
  local dmg_temp="${DMG_DIR}/${APP_NAME}-temp.dmg"

  rm -rf "${DMG_DIR}"
  mkdir -p "${DMG_DIR}"

  # Create a temporary DMG
  local staging="${DMG_DIR}/staging"
  mkdir -p "${staging}"
  cp -R "${app_bundle}" "${staging}/"

  # Create Applications symlink
  ln -s /Applications "${staging}/Applications"

  # Create DMG
  hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${staging}" \
    -ov -format UDRW \
    "${dmg_temp}"

  # Convert to compressed read-only DMG
  hdiutil convert "${dmg_temp}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${dmg_path}"

  rm -f "${dmg_temp}"
  rm -rf "${staging}"

  # Sign the DMG (unless skipping)
  if [[ "${SKIP_SIGN}" == "false" ]]; then
    codesign --force --sign "${SIGNING_IDENTITY}" "${dmg_path}"
  fi

  echo "    DMG created at: ${dmg_path}"
}

notarize_dmg() {
  local dmg_path="${DMG_DIR}/${APP_NAME}.dmg"

  echo "    Submitting to Apple for notarization..."
  xcrun notarytool submit "${dmg_path}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

  echo "    Notarization complete"
}

staple_dmg() {
  local dmg_path="${DMG_DIR}/${APP_NAME}.dmg"

  xcrun stapler staple "${dmg_path}"
  echo "    Stapled notarization ticket to DMG"
}

create_git_tag_and_release() {
  local tag="v${RELEASE_VERSION}"
  local dmg_path="${DMG_DIR}/${APP_NAME}.dmg"
  local versioned_dmg="${DMG_DIR}/${APP_NAME}-${RELEASE_VERSION}.dmg"

  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to create tags" >&2
    exit 1
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: GitHub CLI (gh) is required to create releases" >&2
    exit 1
  fi

  if [[ ! -f "${dmg_path}" ]]; then
    echo "Error: DMG not found at ${dmg_path}" >&2
    exit 1
  fi

  cp "${dmg_path}" "${versioned_dmg}"

  if git rev-parse "${tag}" >/dev/null 2>&1; then
    echo "Error: tag ${tag} already exists" >&2
    exit 1
  fi

  git tag "${tag}"
  git push origin "${tag}"

  gh release create "${tag}" \
    "${versioned_dmg}" \
    --generate-notes \
    --title "${APP_NAME} ${RELEASE_VERSION}"
}

main "$@"
