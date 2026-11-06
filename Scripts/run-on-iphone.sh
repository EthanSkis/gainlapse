#!/bin/zsh
# Builds Gainlapse with the paid team and installs it on the connected iPhone.
set -euo pipefail

BUNDLE_ID=com.ethangardner.gainlapse
BUILD_DEVICE_ID=00008101-000D65D21A89001E
DEVICECTL_ID=ADE3F368-9774-507C-A7B4-7DC7548F5822
export DEVELOPER_DIR="$HOME/Applications/Xcode-26.3.0.app/Contents/Developer"
PROJECT_DIR="${0:A:h:h}"
WORK_DIR="${TMPDIR:-/tmp}/GainlapseDevice"
mkdir -p "$WORK_DIR"

DEVICES=$(xcrun devicectl list devices 2>&1 || true)
if ! print -r -- "$DEVICES" | grep -E "$DEVICECTL_ID.*(available|connected)" > /dev/null; then
    echo "$DEVICES"
    echo "iPhone not found. Plug it in, unlock it, tap Trust, and try again."
    exit 1
fi

echo "Building for iPhone..."
xcodebuild -project "$PROJECT_DIR/Gainlapse.xcodeproj" -scheme Gainlapse -configuration Debug \
    -destination "id=$BUILD_DEVICE_ID" -derivedDataPath "$WORK_DIR/build" -allowProvisioningUpdates \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build > "$WORK_DIR/build.log" 2>&1 || {
    grep -E 'error:' "$WORK_DIR/build.log" | sort -u
    echo "Build failed. Full log: $WORK_DIR/build.log"
    exit 1
}

APP="$WORK_DIR/build/Build/Products/Debug-iphoneos/Gainlapse.app"
xcrun devicectl device install app --device "$DEVICECTL_ID" "$APP"
xcrun devicectl device process launch --device "$DEVICECTL_ID" "$BUNDLE_ID"
echo "Gainlapse is running on your iPhone."
