#!/bin/sh
set -eu

version=${1:-0.1.1}
case "$version" in
  ''|*[!0-9.]*) echo "버전은 0.1.0처럼 입력해 주세요." >&2; exit 2 ;;
esac
repo='yuseungyeol-823/dambak-md'
asset="DambakMD-v${version}-macOS.zip"
base="https://github.com/${repo}/releases/download/v${version}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$base/$asset" -o "$tmp/$asset"
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$base/$asset.sha256" -o "$tmp/$asset.sha256"
(cd "$tmp" && shasum -a 256 -c "$asset.sha256")
mkdir "$tmp/unpacked"
/usr/bin/ditto -x -k "$tmp/$asset" "$tmp/unpacked"
app="$tmp/unpacked/담백 MD.app"
if [ ! -f "$app/Contents/Info.plist" ] || [ ! -x "$app/Contents/MacOS/DambakMD" ]; then
  echo "릴리스 ZIP에 앱이 없습니다." >&2
  exit 1
fi
mkdir -p "$HOME/Applications"
/usr/bin/ditto "$app" "$HOME/Applications/담백 MD.app"
echo "설치 완료: $HOME/Applications/담백 MD.app"
