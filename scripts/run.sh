#!/bin/bash
set -uo pipefail

SIM_URL="${SIM_URL:-https://expo.dev/artifacts/eas/2GfHMCst2pVra1E_6hKFsi9a3MyraFnildyeHxHjV00.tar.gz}"
BUNDLE_ID="com.lixing.hvacfieldcalc"

echo "== fetch simulator build =="
curl -fL -o sim.tar.gz "$SIM_URL" || exit 1
mkdir -p build
tar -xzf sim.tar.gz -C build || exit 1
APP=$(find build -maxdepth 5 -name "*.app" | head -1)
echo "APP=$APP"
[ -d "$APP" ] || exit 1

echo "== install maestro =="
curl -Ls "https://get.maestro.mobile.dev" | bash
export PATH="$HOME/.maestro/bin:$PATH"
[ -x "$HOME/.maestro/bin/maestro" ] && echo "maestro present" || echo "maestro MISSING"

echo "== available devices =="
xcrun simctl list devices available | sed -n '1,60p'

udid_of() {
  xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1
}

resolve() {
  for c in "iPhone 17 Pro Max" "iPhone 16 Pro Max" "iPhone 17 Plus" "iPhone 15 Pro Max" "iPhone 17 Pro" "iPhone 16 Pro" "iPhone 17" "iPhone 16"; do
    u=$(udid_of "$c")
    if [ -n "$u" ]; then echo "$c|$u"; return; fi
  done
  echo "NONE|"
}

mkdir -p shots
BIG=$(resolve)
BIG_NAME=${BIG%%|*}
BIG_UDID=${BIG##*|}
echo "big=$BIG_NAME $BIG_UDID"

shoot() {
  local NAME="$1" DEV="$2" TAG="$3"
  if [ -z "$DEV" ]; then echo "skip $NAME: no device"; return 0; fi
  echo "== $NAME -> $DEV =="
  xcrun simctl boot "$DEV" || true
  xcrun simctl bootstatus "$DEV" -b || true
  xcrun simctl status_bar "$DEV" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
  xcrun simctl install "$DEV" "$APP" || { echo "install failed"; return 0; }
  xcrun simctl launch "$DEV" "$BUNDLE_ID" || true
  sleep 8
  maestro hierarchy > "shots/hier_before_$TAG.txt" 2>&1 || true
  maestro test --test-output-dir "$PWD/out_$TAG" flow.yaml > "shots/log_$TAG.txt" 2>&1 || true
  tail -80 "shots/log_$TAG.txt"
  maestro hierarchy > "shots/hier_after_$TAG.txt" 2>&1 || true
  find "out_$TAG" -name "*.png" 2>/dev/null | while read -r f; do
    cp "$f" "shots/${TAG}_$(basename "$f")"
  done
  xcrun simctl uninstall "$DEV" "$BUNDLE_ID" || true
  xcrun simctl shutdown "$DEV" || true
}

shoot "$BIG_NAME" "$BIG_UDID" "big"

echo "== result =="
ls -la shots
for p in shots/*.png; do
  [ -e "$p" ] || continue
  echo "$p $(sips -g pixelWidth -g pixelHeight "$p" | tr '\n' ' ')"
done
