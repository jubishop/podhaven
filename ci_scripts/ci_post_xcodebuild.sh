#!/bin/bash
set -euo pipefail

if [ "${CI_XCODEBUILD_EXIT_CODE}" -ne 0 ]; then
  echo "Build failed, skipping tag."
  exit 0
fi

# Read the version that was actually built
plist="${CI_ARCHIVE_PATH}/Products/Applications/${CI_PRODUCT}.app/Info.plist"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
tag="v${version}b${CI_BUILD_NUMBER}"

git tag "$tag" "$CI_COMMIT"
git push origin "$tag"
echo "Tagged ${CI_COMMIT} as ${tag}"
