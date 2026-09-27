#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release --arch x86_64 --scratch-path .build-x86
swift build -c release --arch arm64 --scratch-path .build-arm
X86_BIN=$(swift build -c release --arch x86_64 --scratch-path .build-x86 --show-bin-path)
ARM_BIN=$(swift build -c release --arch arm64 --scratch-path .build-arm --show-bin-path)
APP=".build/담백 MD.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$X86_BIN/DambakMD" "$ARM_BIN/DambakMD" -output "$APP/Contents/MacOS/DambakMD"
cp Sources/DambakMD/Resources/Info.plist "$APP/Contents/Info.plist"
cp -R "$ARM_BIN/DambakMD_DambakMD.bundle" "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
lipo -info "$APP/Contents/MacOS/DambakMD"
