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

# Resolve the first available iPhone simulator for this scheme
SIM_DESTINATION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
  | grep 'platform:iOS Simulator.*OS:.*name:iPhone' \
  | head -1 \
  | sed 's/.*name://' | sed 's/ *}$//')

if [[ -z "$SIM_DESTINATION" ]]; then
  echo "error: No iPhone simulator found. Install one via Xcode." >&2
  exit 1
fi

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

# Preflight: block deploys from a dirty or incomplete working tree
if [[ -n $(git -C "$PROJECT_DIR" status --porcelain) ]]; then
  echo "error: Uncommitted or untracked changes detected — commit before deploying." >&2
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

if [[ -z "$version" ]]; then
  echo "error: Could not determine MARKETING_VERSION from build settings." >&2
  exit 1
fi

tag="v${version}b${build}"

prev_tag=$(git -C "$PROJECT_DIR" tag -l "v*b*" --sort=version:refname | tail -1)
prev_tag_commit=$(git -C "$PROJECT_DIR" rev-parse "${prev_tag}^{commit}" 2>/dev/null || true)
head_commit=$(git -C "$PROJECT_DIR" rev-parse HEAD)

if [[ -n "$prev_tag" && "$prev_tag_commit" == "$head_commit" ]]; then
  # Latest tag points at HEAD — recover from a prior interrupted deploy.
  remote_exists=false
  if git -C "$PROJECT_DIR" ls-remote --tags origin "$prev_tag" | grep -q .; then
    remote_exists=true
  fi

  if [[ "$remote_exists" == true ]] && gh release view "$prev_tag" &>/dev/null; then
    echo "==> ${prev_tag} is already fully deployed. Nothing to do."
    exit 0
  fi

  if [[ "$remote_exists" == true ]]; then
    tag_message=$(git -C "$PROJECT_DIR" tag -l --format='%(contents)' "$prev_tag")
    echo "==> ${prev_tag} was pushed but has no GitHub release. Creating..."
    gh release create "$prev_tag" --title "$prev_tag" --notes "$tag_message"
    echo "==> Done."
    exit 0
  fi

  # Tag exists locally but was never pushed — resume the deploy.
  tag="$prev_tag"
  build="${prev_tag##*b}"
  tag_message=$(git -C "$PROJECT_DIR" tag -l --format='%(contents)' "$prev_tag")
  echo "==> Resuming interrupted deploy for ${tag}..."
else
  # Normal path: generate summary and create a new tag.
  if [[ -z "$prev_tag" ]]; then
    echo "error: No previous tag found. Cannot generate summary." >&2
    exit 1
  fi

  echo "==> Generating release summary (${prev_tag}..HEAD)..."
  diff_content=$(set +o pipefail; git -C "$PROJECT_DIR" diff "${prev_tag}..HEAD" | head -c 50000)

  if [[ -z "$diff_content" ]]; then
    echo "error: No changes to deploy since ${prev_tag}." >&2
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

  git -C "$PROJECT_DIR" tag -a "$tag" -m "$tag_message"
fi

echo "==> Build ${build} (${tag}) from ${commit}"

# On exit: clean up on failure, finalize on success.
DEPLOY_SUCCEEDED=false
on_exit() {
  if [[ "$DEPLOY_SUCCEEDED" != true ]]; then
    echo "error: Deploy failed — rolling back local tag ${tag}..." >&2
    git -C "$PROJECT_DIR" tag -d "$tag" 2>/dev/null
  else
    git -C "$PROJECT_DIR" push origin "$tag" 2>/dev/null || true
    gh release create "$tag" --title "$tag" --notes "$tag_message" 2>/dev/null || true
    echo "==> Done. Tagged ${commit} as ${tag}"
  fi
  rm -rf "$PROJECT_DIR/build"
  rm -rf ~/Library/Developer/Xcode/Archives/*/"PodHaven "*
}
trap on_exit EXIT

# Run tests
echo "==> Running tests..."
TEST_LOG="$PROJECT_DIR/build/xcodebuild-test.log"
mkdir -p "$PROJECT_DIR/build"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIM_DESTINATION" \
  2>&1 | tee "$TEST_LOG" | xcbeautify
echo "==> Tests passed."

# Archive
echo "==> Archiving..."
BUILD_LOG="$PROJECT_DIR/build/xcodebuild-archive.log"
mkdir -p "$PROJECT_DIR/build"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
  CURRENT_PROJECT_VERSION="$build" \
  2>&1 | tee "$BUILD_LOG" | xcbeautify

# Export and upload
echo "==> Uploading to App Store Connect..."
UPLOAD_LOG="$PROJECT_DIR/build/xcodebuild-upload.log"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
  2>&1 | tee "$UPLOAD_LOG" | xcbeautify

# Signal success — the EXIT trap handles the rest.
DEPLOY_SUCCEEDED=true
