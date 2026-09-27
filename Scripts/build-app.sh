#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if xcodebuild -version >/dev/null 2>&1; then
  swift build -c release
elif [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
  SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build -c release
else
  swift build -c release
fi
APP=".build/담백 MD.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DambakMD "$APP/Contents/MacOS/DambakMD"
cp Sources/DambakMD/Resources/Info.plist "$APP/Contents/Info.plist"
cp -R .build/release/DambakMD_DambakMD.bundle "$APP/Contents/Resources/"
print "완료: $APP"
