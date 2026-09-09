#!/bin/bash
set -euo pipefail

# Archive and upload PodHaven, optionally distributing to Everyone in TestFlight.
#
# Usage:
#   ./bin/deploy.sh                         # Uses Xcode-session Apple ID
#   ./bin/deploy.sh --api-key <path> \      # Uses App Store Connect API key
#     --api-key-id <id> \
#     --api-issuer-id <issuer>
#   ASC_KEY_PATH=<path> ASC_KEY_ID=<id> ASC_ISSUER_ID=<issuer> ./bin/deploy.sh
#   ./bin/shipit --notes "What changed"     # Also submit to Everyone

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/PodHaven.xcodeproj"
SCHEME="PodHaven"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

# Parse arguments
API_KEY_PATH="${ASC_KEY_PATH:-}"
API_KEY_ID="${ASC_KEY_ID:-}"
API_ISSUER_ID="${ASC_ISSUER_ID:-}"
FORCE=false
TESTFLIGHT_NOTES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'HELP'
Usage: bin/shipit [--notes "What changed"] [-f] [API key options]

No --notes: test, archive, and upload only.
--notes TEXT: also wait for processing and submit to the external Everyone group.
              Repeating the command retries distribution of the same uploaded commit.
-f, --force: allow a branch other than main (a clean working tree is still required).
--api-key PATH --api-key-id ID --api-issuer-id ID: use an App Store Connect API key.
API keys can also use ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID.
Without an API key, uploads use Xcode's login; distribution uses Fastlane's Apple ID login.
Use FASTLANE_USER to select that Apple ID. Fastlane may request two-factor authentication.
-h, --help: show this help.

Processing is checked every 30 seconds for up to 30 minutes. Apple beta review may take longer.
Successful uploads publish a Git tag and GitHub release and mirror to SourceHut.
bin/deploy.sh accepts the same options.
HELP
      exit 0
      ;;
    --notes)
      if [[ $# -lt 2 || ! "$2" =~ [^[:space:]] || "$2" == --* ]]; then
        echo 'error: --notes requires nonblank text, such as --notes "Fixed playback".' >&2
        exit 1
      fi
      TESTFLIGHT_NOTES="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    --api-key)
      if [[ $# -lt 2 ]]; then echo 'error: --api-key requires a path.' >&2; exit 1; fi
      API_KEY_PATH="$2"
      shift 2
      ;;
    --api-key-id)
      if [[ $# -lt 2 ]]; then echo 'error: --api-key-id requires an ID.' >&2; exit 1; fi
      API_KEY_ID="$2"
      shift 2
      ;;
    --api-issuer-id)
      if [[ $# -lt 2 ]]; then echo 'error: --api-issuer-id requires an ID.' >&2; exit 1; fi
      API_ISSUER_ID="$2"
      shift 2
      ;;
    *)
      echo "error: Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

AUTH_FLAGS=()
auth_value_count=0
[[ -n "$API_KEY_PATH" ]] && ((auth_value_count += 1))
[[ -n "$API_KEY_ID" ]] && ((auth_value_count += 1))
[[ -n "$API_ISSUER_ID" ]] && ((auth_value_count += 1))

if (( auth_value_count > 0 && auth_value_count < 3 )); then
  echo "error: App Store Connect API auth requires ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID." >&2
  echo "error: Or pass --api-key, --api-key-id, and --api-issuer-id." >&2
  exit 1
fi

if (( auth_value_count == 3 )); then
  if [[ ! -f "$API_KEY_PATH" ]]; then
    echo "error: App Store Connect API key not found: $API_KEY_PATH" >&2
    exit 1
  fi

  API_KEY_PATH="$(cd "$(dirname "$API_KEY_PATH")" && pwd)/$(basename "$API_KEY_PATH")"

  AUTH_FLAGS=(
    -authenticationKeyPath "$API_KEY_PATH"
    -authenticationKeyID "$API_KEY_ID"
    -authenticationKeyIssuerID "$API_ISSUER_ID"
  )
fi

run_testflight() {
  (
    cd "$PROJECT_DIR"
    ASC_KEY_PATH="$API_KEY_PATH" ASC_KEY_ID="$API_KEY_ID" ASC_ISSUER_ID="$API_ISSUER_ID" \
      PODHAVEN_TESTFLIGHT_NOTES="$TESTFLIGHT_NOTES" \
      FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_HIDE_CHANGELOG=1 FASTLANE_OPT_OUT_USAGE=1 FASTLANE_SKIP_DOCS=1 \
      fastlane distribute_testflight "$@"
  )
}

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

if [[ -n "$TESTFLIGHT_NOTES" ]]; then
  if ! command -v fastlane &>/dev/null; then
    echo 'error: --notes requires Fastlane. Install with: brew install fastlane' >&2
    exit 1
  fi
  run_testflight preflight:true
fi

# Resolve the first available iPhone simulator for this scheme.
SIM_DESTINATION=$(xcodebuild -hideShellScriptEnvironment -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
  | grep 'platform:iOS Simulator.*OS:.*name:iPhone' \
  | head -1 \
  | sed 's/.*name://' | sed 's/ *}$//')

if [[ -z "$SIM_DESTINATION" ]]; then
  echo "error: No iPhone simulator found. Install one via Xcode." >&2
  exit 1
fi

UPLOAD_SUCCEEDED=false
UPLOAD_RECEIPT=$(git -C "$PROJECT_DIR" rev-parse --path-format=absolute --git-path podhaven-last-upload)

# Calculate next build number from git tags
last_build=$(git -C "$PROJECT_DIR" tag -l "v*b*" \
  | sed 's/v.*b//' \
  | sort -n \
  | tail -1)
build=$(( ${last_build:-0} + 1 ))
commit=$(git -C "$PROJECT_DIR" rev-parse --short HEAD)
version=$(xcodebuild -hideShellScriptEnvironment -project "$PROJECT" -scheme "$SCHEME" \
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

  if [[ "$remote_exists" == true || ( -f "$UPLOAD_RECEIPT" && "$(cat "$UPLOAD_RECEIPT")" == "$prev_tag" ) ]]; then
    UPLOAD_SUCCEEDED=true
  fi

  if [[ -z "$TESTFLIGHT_NOTES" && "$remote_exists" == true ]] && gh release view "$prev_tag" &>/dev/null; then
    echo "==> ${prev_tag} is already fully deployed. Nothing to do."
    exit 0
  fi

  if [[ -z "$TESTFLIGHT_NOTES" && "$remote_exists" == true ]]; then
    tag_message=$(git -C "$PROJECT_DIR" tag -l --format='%(contents)' "$prev_tag")
    echo "==> ${prev_tag} was pushed but has no GitHub release. Creating..."
    gh release create "$prev_tag" --title "$prev_tag" --notes "$tag_message"
    echo "==> Done."
    exit 0
  fi

  # Reuse the tagged build for a retry or distribution after an upload-only run.
  tag="$prev_tag"
  build="${prev_tag##*b}"
  version="${prev_tag#v}"
  version="${version%b*}"
  tag_message=$(git -C "$PROJECT_DIR" tag -l --format='%(contents)' "$prev_tag")
  echo "==> Reusing ${tag}..."
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

# Per-run scratch dir under /tmp for the archive and all xcodebuild logs.
LOG_DIR=$(mktemp -d "/tmp/podhaven-deploy.XXXXXX")
ARCHIVE_PATH="$LOG_DIR/PodHaven.xcarchive"
echo "==> Logs and archive: $LOG_DIR"

# On exit: clean up on failure, finalize on success.
DEPLOY_SUCCEEDED=false
CURRENT_PHASE=""
CURRENT_LOG=""
on_exit() {
  local exit_code=$?
  if [[ "$DEPLOY_SUCCEEDED" != true ]]; then
    {
      echo ""
      if [[ -n "$CURRENT_PHASE" ]]; then
        echo "error: Deploy failed during: ${CURRENT_PHASE} (exit ${exit_code})"
      else
        echo "error: Deploy failed (exit ${exit_code})."
      fi
      if [[ -n "$CURRENT_LOG" && -f "$CURRENT_LOG" ]]; then
        echo "==> Log: ${CURRENT_LOG}"
      fi
      if [[ -n "${LOG_DIR:-}" ]]; then
        echo "==> All logs and artifacts: ${LOG_DIR}"
      fi
      if [[ "$UPLOAD_SUCCEEDED" == true ]]; then
        echo "error: ${tag} was uploaded. Run bin/shipit again with the same --notes to retry distribution."
      else
        echo "error: Rolling back local tag ${tag}..."
      fi
    } >&2
    if [[ "$UPLOAD_SUCCEEDED" != true ]]; then
      git -C "$PROJECT_DIR" tag -d "$tag" 2>/dev/null
    fi
    # Leave $LOG_DIR in place so the log above can be re-read after the script exits.
  else
    git -C "$PROJECT_DIR" push origin "$tag" 2>/dev/null || true
    echo "==> Mirroring ${branch} and ${tag} to sourcehut..."
    git -C "$PROJECT_DIR" push sourcehut "$branch" || echo "warning: sourcehut push of ${branch} failed" >&2
    git -C "$PROJECT_DIR" push sourcehut "$tag" || echo "warning: sourcehut push of ${tag} failed" >&2
    gh release create "$tag" --title "$tag" --notes "$tag_message" 2>/dev/null || true
    echo "==> Done. Tagged ${commit} as ${tag}"
    rm -rf "$LOG_DIR"
    rm -rf ~/Library/Developer/Xcode/Archives/*/"PodHaven "*
  fi
}
trap on_exit EXIT

# Run an xcodebuild pipeline so its exit code (not tee/xcbeautify's) drives failure.
# xcbeautify can swallow xcodebuild's stderr; PIPESTATUS[0] preserves the real status.
run_xcodebuild() {
  local phase="$1"
  local log="$2"
  shift 2
  CURRENT_PHASE="$phase"
  CURRENT_LOG="$log"
  mkdir -p "$(dirname "$log")"
  # Suspend errexit so PIPESTATUS survives for inspection. `|| true` would reset it,
  # because PIPESTATUS reflects the *most recently executed* pipeline (i.e. `true`).
  set +e
  xcodebuild -hideShellScriptEnvironment "$@" 2>&1 | tee "$log" | xcbeautify
  local status=${PIPESTATUS[0]}
  set -e
  if (( status != 0 )); then
    exit "$status"
  fi
}

if [[ "$UPLOAD_SUCCEEDED" != true ]]; then
  # Run tests
  echo "==> Running tests..."
  TEST_LOG="$LOG_DIR/xcodebuild-test.log"
  run_xcodebuild "tests" "$TEST_LOG" \
    test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$SIM_DESTINATION"
  echo "==> Tests passed."

  # Archive
  echo "==> Archiving..."
  BUILD_LOG="$LOG_DIR/xcodebuild-archive.log"
  run_xcodebuild "archive" "$BUILD_LOG" \
    archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
    CURRENT_PROJECT_VERSION="$build"

  # Export and upload
  echo "==> Uploading to App Store Connect..."
  UPLOAD_LOG="$LOG_DIR/xcodebuild-upload.log"
  run_xcodebuild "upload" "$UPLOAD_LOG" \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}"

  UPLOAD_SUCCEEDED=true
  printf '%s\n' "$tag" > "${UPLOAD_RECEIPT}.tmp"
  mv "${UPLOAD_RECEIPT}.tmp" "$UPLOAD_RECEIPT"
fi

if [[ -n "$TESTFLIGHT_NOTES" ]]; then
  CURRENT_PHASE="TestFlight distribution"
  CURRENT_LOG="$LOG_DIR/testflight.log"
  echo '==> Waiting for processing and submitting to Everyone...'
  run_testflight "version:$version" "build:$build" 2>&1 | tee "$CURRENT_LOG"
fi

# Signal success — the EXIT trap handles the rest.
DEPLOY_SUCCEEDED=true
