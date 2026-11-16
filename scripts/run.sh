#!/bin/bash
set -euo pipefail

echo "== fetch simulator build =="
curl -fL -o sim.tar.gz "https://expo.dev/artifacts/eas/4gSgl9m1ngCMsOweAvPLJGwfXOcM3Ir4Aso7heQWrs8.tar.gz"
mkdir -p build
tar -xzf sim.tar.gz -C build
APP=$(find build -maxdepth 4 -name "SiteMath.app" | head -1)
echo "APP=$APP"
test -d "$APP"

echo "== install maestro =="
set +e
curl -Ls "https://get.maestro.mobile.dev" | bash
set -e
export PATH="$HOME/.maestro/bin:$PATH"
test -x "$HOME/.maestro/bin/maestro" && echo "maestro present" || echo "maestro MISSING"

mkdir -p shots
for NAME in "iPhone 15 Pro Max" "iPhone 15 Pro"; do
  DEV=$(xcrun simctl list devices available | grep -F "  $NAME (" | head -1 | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)
  echo "== $NAME -> $DEV =="
  if [ -z "$DEV" ]; then echo "device not found: $NAME"; continue; fi
  xcrun simctl boot "$DEV" || true
  xcrun simctl bootstatus "$DEV" -b || true
  xcrun simctl status_bar "$DEV" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
  xcrun simctl install "$DEV" "$APP"
  xcrun simctl launch "$DEV" com.lixing.sitemath
  sleep 5
  TAG=$(echo "$NAME" | tr ' ' '_')
  set +e
  maestro test --test-output-dir "$PWD/out_$TAG" flow.yaml > "shots/log_$TAG.txt" 2>&1
  set -e
  tail -30 "shots/log_$TAG.txt" || true
  find "out_$TAG" -name "*.png" -print0 2>/dev/null | while IFS= read -r -d '' f; do
    cp "$f" "shots/${TAG}_$(basename "$f")"
  done
  xcrun simctl uninstall "$DEV" com.lixing.sitemath || true
  xcrun simctl shutdown "$DEV" || true
done

echo "== result =="
ls -la shots
for p in shots/*.png; do
  [ -e "$p" ] || continue
  echo "$p $(sips -g pixelWidth -g pixelHeight "$p" | tr '\n' ' ')"
done
