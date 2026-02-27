#!/bin/bash
set -euo pipefail

# deploy.sh — Archive and upload PodHaven to TestFlight.
#
# Usage:
#   ./Tools/deploy.sh                       # Uses Xcode-session Apple ID
#   ./Tools/deploy.sh --api-key <path> \    # Uses App Store Connect API key
#     --api-key-id <id> \
#     --api-issuer-id <issuer>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/PodHaven.xcodeproj"
SCHEME="PodHaven"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"
ARCHIVE_PATH="$PROJECT_DIR/build/PodHaven.xcarchive"

# Parse optional API key arguments
AUTH_FLAGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)
      AUTH_FLAGS+=(-authenticationKeyPath "$2")
      shift 2
      ;;
    --api-key-id)
      AUTH_FLAGS+=(-authenticationKeyID "$2")
      shift 2
      ;;
    --api-issuer-id)
      AUTH_FLAGS+=(-authenticationKeyIssuerID "$2")
      shift 2
      ;;
    *)
      echo "error: Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Require xcbeautify for formatted build output
if ! command -v xcbeautify &>/dev/null; then
  echo "error: xcbeautify not found. Install with: brew install xcbeautify" >&2
  exit 1
fi

# Preflight: block deploys from a dirty working tree
if ! git -C "$PROJECT_DIR" diff --quiet HEAD; then
  echo "error: Uncommitted changes detected — commit before deploying." >&2
  exit 1
fi

# Calculate next build number from git tags
last_build=$(git -C "$PROJECT_DIR" tag -l "v*b*" \
  | sed 's/v.*b//' \
  | sort -n \
  | tail -1)
build=$(( ${last_build:-0} + 1 ))
commit=$(git -C "$PROJECT_DIR" rev-parse --short HEAD)
version=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -showBuildSettings 2>/dev/null \
  | grep '^\s*MARKETING_VERSION' \
  | head -1 \
  | sed 's/.*= //')
tag="v${version}b${build}"

echo "==> Build ${build} (${tag}) from ${commit}"

# Archive
echo "==> Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
  CURRENT_PROJECT_VERSION="$build" \
  2>&1 | xcbeautify --preserve-unbeautified

# Export and upload
echo "==> Uploading to App Store Connect..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
  2>&1 | xcbeautify --preserve-unbeautified

# Tag only after successful upload
git -C "$PROJECT_DIR" tag "$tag"
git -C "$PROJECT_DIR" push origin "$tag"

# Clean up
rm -rf "$PROJECT_DIR/build"

echo "==> Done. Tagged ${commit} as ${tag}"
