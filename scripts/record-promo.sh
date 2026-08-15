#!/bin/bash
# PV の素材を撮る。
#
# スタブではなく本物の MapKit で動かす。現在地は simctl で与える。
# 履歴や保存地点が残っていると画に映るので、毎回入れ直してから撮る。
#
#   scripts/record-promo.sh [出力先ディレクトリ]
set -euo pipefail

out="${1:-artifacts/promo}"
sim="${PROMO_SIM:-iPhone 17}"
bundle="com.usefulmap.UsefulMap"
# 東京ディズニーランド
location="${PROMO_LOCATION:-35.6329,139.8804}"

mkdir -p "$out"
id=$(xcrun simctl list devices available | grep -m1 "$sim (" | grep -oE '[0-9A-F-]{36}')
test -n "$id" || { echo "シミュレータが見つかりません: $sim" >&2; exit 1; }

xcrun simctl boot "$id" 2>/dev/null || true
xcodegen generate
xcodebuild build -project UsefulMap.xcodeproj -scheme UsefulMap \
  -destination "id=$id" -derivedDataPath build/sim -quiet

xcrun simctl uninstall "$id" "$bundle" 2>/dev/null || true
xcrun simctl install "$id" build/sim/Build/Products/Debug-iphonesimulator/UsefulMap.app
xcrun simctl privacy "$id" grant location-always "$bundle"
xcrun simctl location "$id" set "$location"
xcrun simctl ui "$id" appearance light

rm -f "$out/raw.mov"
xcrun simctl io "$id" recordVideo --codec h264 --force "$out/raw.mov" &
recorder=$!
sleep 2

xcodebuild test -project UsefulMap.xcodeproj -scheme UsefulMap \
  -destination "id=$id" -only-testing:UsefulMapUITests/PromoRecording

kill -INT $recorder
wait $recorder 2>/dev/null || true
echo "素材: $out/raw.mov"
