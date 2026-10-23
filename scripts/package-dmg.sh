#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
version="${KEYCHRON_RELEASE_VERSION:-1.1.0-preview.1}"
[[ "$version" =~ '^[A-Za-z0-9.-]+$' ]] || { print -u2 'Invalid release version'; exit 1; }
KEYCHRON_SIGNING_IDENTITY=- zsh build.sh
mkdir -p dist
stage=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto build/KeychronMenu.app "$stage/KeychronMenu.app"
ln -s /Applications "$stage/Applications"
cp docs/INSTALL.html "$stage/Start Here.html"
cp LICENSE THIRD_PARTY_NOTICES.md "$stage/"
image="$PWD/dist/KeychronMenu-$version-arm64.dmg"
hdiutil create -ov -volname 'Keychron Menu' -srcfolder "$stage" -fs HFS+ -format UDZO "$image"
hdiutil verify "$image"
codesign --verify --deep --strict build/KeychronMenu.app
(cd dist && shasum -a 256 "${image:t}" > "${image:t}.sha256")
print "$image"
