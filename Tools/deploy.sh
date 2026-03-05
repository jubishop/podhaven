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

# Parse arguments
AUTH_FLAGS=()
FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE=true
      shift
      ;;
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

# Require llm for AI-generated tag summaries
if ! command -v llm &>/dev/null; then
  echo "error: llm not found. Install with: pipx install llm" >&2
  exit 1
fi

# Require gh for creating GitHub releases
if ! command -v gh &>/dev/null; then
  echo "error: gh not found. Install with: brew install gh" >&2
  exit 1
fi

# Preflight: block deploys from non-main branches
branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD)
if [[ "$branch" != "main" && "$FORCE" != true ]]; then
  echo "error: Not on main branch (on '$branch'). Use -f to deploy anyway." >&2
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

# Generate AI release summary before archiving
prev_tag=$(git -C "$PROJECT_DIR" tag -l "v*b*" --sort=version:refname | tail -1)

if [[ -z "$prev_tag" ]]; then
  echo "error: No previous tag found. Cannot generate summary." >&2
  exit 1
fi

echo "==> Generating release summary (${prev_tag}..HEAD)..."
diff_content=$(git -C "$PROJECT_DIR" diff "${prev_tag}..HEAD" | head -c 50000)

if [[ -z "$diff_content" ]]; then
  echo "error: No diff between ${prev_tag} and HEAD." >&2
  exit 1
fi

tag_message=$(echo "$diff_content" | llm -s \
  "Summarize this code diff for release notes. Write for a technically savvy end user. Focus on user-facing improvements, new features, and bug fixes. Be concise — a few bullet points or a short paragraph.")

if [[ -z "$tag_message" ]]; then
  echo "error: llm returned empty summary." >&2
  exit 1
fi

echo "==> Summary generated:"
echo ""
echo "$tag_message"
echo ""

# Create and push tag before uploading so it's never lost
git -C "$PROJECT_DIR" tag -a "$tag" -m "$tag_message"
git -C "$PROJECT_DIR" push origin "$tag"

# Roll back the tag if anything below fails
rollback_tag() {
  echo "error: Deploy failed — rolling back tag ${tag}..." >&2
  git -C "$PROJECT_DIR" tag -d "$tag" 2>/dev/null
  git -C "$PROJECT_DIR" push origin --delete "$tag" 2>/dev/null
}
trap rollback_tag ERR

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
  2>&1 | xcbeautify

# Export and upload
echo "==> Uploading to App Store Connect..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
  2>&1 | xcbeautify

# Upload succeeded — disable rollback and create GitHub release
trap - ERR
gh release create "$tag" --title "$tag" --notes "$tag_message"

# Clean up
rm -rf "$PROJECT_DIR/build"
rm -rf ~/Library/Developer/Xcode/Archives/*/"PodHaven "*

echo "==> Done. Tagged ${commit} as ${tag}"
