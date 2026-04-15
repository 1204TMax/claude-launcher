#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/claude-launcher.xcodeproj"
SCHEME="ClaudeLauncher"
APP_NAME="ClaudeLauncher"
BUILD_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DIST_DIR="$ROOT_DIR/dist"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DMG_BACKGROUND="$BUILD_DIR/dmg-background.png"
DMG_RW_PATH="$BUILD_DIR/$APP_NAME-temp.dmg"
cleanup() {
  rm -rf "$STAGING_DIR" "$DMG_BACKGROUND" "$DMG_RW_PATH"
}
trap cleanup EXIT

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "未找到 Xcode 工程: $PROJECT_PATH" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$STAGING_DIR" "$DMG_BACKGROUND"

create_dmg_background() {
  python3 - <<'PY' "$DMG_BACKGROUND"
from PIL import Image, ImageDraw, ImageFont
import sys

output = sys.argv[1]
scale = 2
window_width, window_height = 720, 440
width, height = window_width * scale, window_height * scale
img = Image.new("RGBA", (width, height), (248, 248, 250, 255))
draw = ImageDraw.Draw(img)

for y in range(height):
    ratio = y / max(height - 1, 1)
    color = (
        int(250 - ratio * 6),
        int(250 - ratio * 4),
        int(252 - ratio * 2),
        255,
    )
    draw.line((0, y, width, y), fill=color)

def s(value):
    return int(value * scale)

card = (s(24), s(24), width - s(24), height - s(24))
draw.rounded_rectangle(card, radius=s(28), fill=(255, 255, 255, 236), outline=(228, 232, 238, 255), width=s(2))

def load_font(size, bold=False):
    candidates = []
    if bold:
        candidates += [
            "/System/Library/Fonts/PingFang.ttc",
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf",
            "/System/Library/Fonts/Supplemental/HelveticaNeue.ttc",
        ]
    candidates += [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/HelveticaNeue.ttc",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()

font_title = load_font(s(38), bold=True)
font_body = load_font(s(20))
font_hint = load_font(s(16), bold=True)
font_badge = load_font(s(15), bold=True)

text_primary = (47, 52, 60, 255)
text_secondary = (109, 117, 130, 255)
arrow_color = (255, 138, 76, 255)

badge = (46, 46, 54, 255)
draw.rounded_rectangle((s(56), s(52), s(170), s(86)), radius=s(16), fill=(247, 248, 250, 255), outline=(235, 238, 243, 255), width=s(1))
draw.text((s(92), s(61)), "安装", font=font_badge, fill=badge)

draw.text((s(56), s(104)), "拖到 Applications 文件夹", font=font_title, fill=text_primary)
draw.text((s(56), s(154)), "将 ClaudeLauncher 拖入 Applications 文件夹即可完成安装。", font=font_body, fill=text_secondary)

start_x, end_x = s(252), s(450)
center_y = s(276)
shaft_top = center_y - s(10)
shaft_bottom = center_y + s(10)

draw.rounded_rectangle((start_x, shaft_top, end_x - s(28), shaft_bottom), radius=s(10), fill=arrow_color)
draw.polygon([(end_x - s(30), center_y - s(32)), (end_x, center_y), (end_x - s(30), center_y + s(32))], fill=arrow_color)

hint_box = (s(220), s(370), s(520), s(404))
draw.rounded_rectangle(hint_box, radius=s(17), fill=(255, 247, 242, 255), outline=(255, 225, 209, 255), width=s(1))
draw.text((s(252), s(379)), "拖到这里完成安装", font=font_hint, fill=(158, 89, 56, 255))

final_img = img.resize((window_width, window_height), Image.Resampling.LANCZOS)
final_img.save(output)
PY
}

create_dmg_background

echo "==> 生成 archive"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "archive 中未找到 app: $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
  VERSION="$TIMESTAMP"
fi

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TEMP_DMG_PATH="$BUILD_DIR/$DMG_NAME"

mkdir -p "$STAGING_DIR/.background"
cp -R "$APP_PATH" "$STAGING_DIR/"
cp "$DMG_BACKGROUND" "$STAGING_DIR/.background/background.png"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> 使用 Developer ID 签名 app"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$STAGING_DIR/$APP_NAME.app"
fi

rm -f "$DMG_PATH" "$TEMP_DMG_PATH" "$DMG_RW_PATH"

echo "==> 创建可定制 DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs APFS \
  -format UDRW \
  -ov \
  "$DMG_RW_PATH"

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW_PATH")"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_APFS/ {print $1; exit}')"
VOLUME_PATH="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
VOLUME_NAME="$(basename "$VOLUME_PATH")"

osascript <<EOF
 tell application "Finder"
   if not (exists alias file "$VOLUME_PATH/Applications") then
     make new alias file at POSIX file "$VOLUME_PATH" to POSIX file "/Applications" with properties {name:"Applications"}
   end if

   tell disk "$VOLUME_NAME"
     open
     set current view of container window to icon view
     set toolbar visible of container window to false
     set statusbar visible of container window to false
     set pathbar visible of container window to false
     set bounds of container window to {120, 120, 840, 560}
     set icon size of icon view options of container window to 128
     set arrangement of icon view options of container window to not arranged
     set background picture of icon view options of container window to POSIX file "$VOLUME_PATH/.background/background.png"
     set position of item "$APP_NAME.app" of container window to {182, 246}
     set position of item "Applications" of container window to {538, 246}
     close
     open
     update without registering applications
     delay 1
   end tell
 end tell
EOF

chmod -Rf go-w "$VOLUME_PATH"
sync
hdiutil detach "$DEVICE"

echo "==> 转换为压缩 DMG"
hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$TEMP_DMG_PATH"
rm -f "$DMG_RW_PATH"

mv "$TEMP_DMG_PATH" "$DMG_PATH"

if [[ -n "${NOTARY_PROFILE:-}" && -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> 提交 DMG 公证"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> 加盖 stapler"
  xcrun stapler staple "$DMG_PATH"
fi

echo "==> 完成"
echo "DMG: $DMG_PATH"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo "注意: 当前 DMG 未签名/未公证，首次打开可能会被 macOS 拦截。"
fi
