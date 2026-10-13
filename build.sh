#!/bin/bash
# 建置 MX Master Mac.app。需要 Xcode（只用它的 swiftc），沒有外部相依。
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI 的巨集外掛只在完整的 Xcode 裡，Command Line Tools 沒有。
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP="build/MX Master Mac.app"
ICON_SOURCE="${ICON_SOURCE:-Resources/app.png}"
# 用固定的開發憑證簽章，重新建置後「輔助使用」「輸入監控」權限才不會失效；沒有憑證時改用臨時簽章。
# 對外發布用 `./build.sh --release`：一律臨時簽章（開發憑證的名稱含個人信箱，不放進公開的檔案），並打包成 zip。
RELEASE=0
[ "${1:-}" = "--release" ] && RELEASE=1
if [ "$RELEASE" = 1 ]; then
    APP="build/release/MX Master Mac.app"
    IDENTITY=""
else
    IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')}"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
    -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement -framework Carbon \
    -o "$APP/Contents/MacOS/MXMasterMac" Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"

if [ -f "$ICON_SOURCE" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# 從別處複製來的檔案可能帶延伸屬性，簽章前要清掉。
xattr -cr "$APP"

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --identifier net.yuchenhome.mxmastermac "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - --identifier net.yuchenhome.mxmastermac "$APP"
    echo "Signed ad hoc (Accessibility permission must be granted again after each build)"
fi
echo "Built: $APP"

if [ "$RELEASE" = 1 ]; then
    ZIP="build/MXMasterMac.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packaged: $ZIP"
    shasum -a 256 "$ZIP"
fi
