#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
bundle="$PWD/build/KeychronMenu.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
swift prepare-icon.swift Assets/KeychronOriginal.png Assets
swift Tests/IconChecks.swift Assets
clang -arch arm64 -Wall -Wextra -Werror -mmacosx-version-min=13.0 Sources/BatteryReader.c -framework IOKit -framework CoreFoundation -o "$bundle/Contents/MacOS/BatteryReader"
clang -arch arm64 -Wall -Wextra -Werror -mmacosx-version-min=13.0 Sources/SleepControl.c -framework IOKit -framework CoreFoundation -o "$bundle/Contents/MacOS/SleepControl"
swiftc -swift-version 6 -target arm64-apple-macosx13.0 Sources/BatteryPolicy.swift Sources/SleepState.swift Sources/ReaderProcess.swift Sources/App.swift -framework AppKit -framework IOKit -framework UserNotifications -framework ServiceManagement -o "$bundle/Contents/MacOS/KeychronMenu"
cp Assets/Keychron.png Assets/Keychron@2x.png "$bundle/Contents/Resources/"
cp Info.plist "$bundle/Contents/Info.plist"
keychron_identity="${KEYCHRON_SIGNING_IDENTITY:-}"
if [[ -z "$keychron_identity" ]]; then
  keychron_identity=$(security find-identity -v -p codesigning | awk '/^[[:space:]]*[0-9]+\)/ && /"Apple Development:/ && !/CSSMERR/ { print $2; exit }')
fi
keychron_identity="${keychron_identity:--}"
codesign --force --timestamp=none --sign "$keychron_identity" "$bundle/Contents/MacOS/BatteryReader"
codesign --force --timestamp=none --sign "$keychron_identity" "$bundle/Contents/MacOS/SleepControl"
codesign --force --timestamp=none --sign "$keychron_identity" "$bundle"
printf '%s\n' "$bundle"
