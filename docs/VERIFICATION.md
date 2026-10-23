# Verification

## Live hardware coverage

The original non-backlit Keychron K2-M1 with Bluetooth firmware 1.08 dated 20210820 was tested on one Apple silicon Mac.

The firmware setting was read directly, changed from OFF to ON, and changed back to OFF. Each change was verified after the keyboard restarted and reconnected. The saved byte and live flag matched, and the neighboring EEPROM bytes were unchanged.

The integrated AppKit menu switch was also exercised programmatically through its actual target/action. It changed OFF → ON → OFF using the production helper, disabled itself while changing, and restored normal availability afterward. The installed app was restarted and read OFF again. Battery readings and existing notification settings remained working.

These checks prove the setting and persistence path on the tested device. They are not a new 30-minute behavioral sleep test, a test of every K2 variant, or a test of every macOS version. Desktop screenshot automation could not bind the windowless accessory app; the menu action was tested programmatically instead.

## Offline checks

Run `zsh test.sh`. This does not query or change a keyboard.

Coverage includes malformed and unsupported firmware replies, read checksum/address/length validation, unexpected changes to neighboring storage bytes, invalid sleep values, battery warning thresholds and rearming, warning persistence, helper timeout recovery, and busy-request rejection.

## Hardware integration test source

`Tests/MenuIntegration.swift` defines a separate hardware-mutating test. It requires an initially OFF supported keyboard, runs the actual menu switch ON and then OFF, and expects verified readback after each change. It is not included in the normal test command. If interrupted after ON, restore the desired setting using the app.

During development it was compiled with the production AppDelegate source, relaxing private visibility for test inspection and replacing only the app entry point. It is not a second shipped application.

## Preview packaging

The disk image is built from source, ad-hoc signed and not notarized. Packaging checks verify its filesystem image, app code signatures and ARM64 executables. They do not replace Apple's notarization or prove a frictionless first launch on another Mac.
