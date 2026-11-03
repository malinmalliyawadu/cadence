#!/usr/bin/env bash
# Archives Cadence and uploads it to App Store Connect for TestFlight.
#
#     scripts/testflight.sh            archive and upload
#     scripts/testflight.sh --no-upload  archive and export an .ipa to build/export only
#
# The build number is the current time (yyyyMMddHHmm), so every upload is unique.
# Needs the App Store Connect app record for nz.malin.cadence.fitness and an Xcode
# account on team WDB2HN7DW7, so -allowProvisioningUpdates can manage signing.
set -euo pipefail

cd "$(dirname "$0")/.."

upload=true
if [[ "${1:-}" == "--no-upload" ]]; then
    upload=false
elif [[ $# -gt 0 ]]; then
    echo "Usage: scripts/testflight.sh [--no-upload]" >&2
    exit 2
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Warning: the working tree has uncommitted changes, and they will be in this build." >&2
fi

archive=build/Cadence.xcarchive
build_number=$(date +%Y%m%d%H%M)

echo "Generating the Xcode project"
xcodegen generate

echo "Archiving build $build_number from $(git rev-parse --abbrev-ref HEAD) at $(git rev-parse --short HEAD)"
rm -rf "$archive" build/export
xcodebuild \
    -project Cadence.xcodeproj \
    -scheme Cadence \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=WDB2HN7DW7 \
    CURRENT_PROJECT_VERSION="$build_number" \
    archive

options=ExportOptions.plist
if [[ "$upload" == false ]]; then
    # Same options, but export locally instead of uploading.
    options=build/ExportOptions-local.plist
    cp ExportOptions.plist "$options"
    plutil -replace destination -string export "$options"
fi

echo "Exporting$([[ "$upload" == true ]] && echo " and uploading to App Store Connect")"
xcodebuild \
    -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$options" \
    -exportPath build/export \
    -allowProvisioningUpdates

if [[ "$upload" == true ]]; then
    echo "Uploaded build $build_number. It appears in TestFlight once App Store Connect has processed it."
else
    echo "Exported build $build_number to build/export."
fi
