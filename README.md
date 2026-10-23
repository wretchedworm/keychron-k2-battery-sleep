# Keychron Menu

Keep your K2 ready to type, and know when it needs a charge.

## Why this exists

This project started with two frustrations on an original Keychron K2:

- **Waiting 4–5 seconds for it to wake up.** Come back after a break, start typing, and wait for the keyboard to respond.
- **No visible battery level on the Mac.** The keyboard could run out of power without a useful warning that it was time to charge.

Keychron Menu puts both controls in the Mac's menu bar. Turn **auto-sleep OFF** to keep the keyboard awake instead of waiting through its sleep/wake cycle. See its reported battery percentage, with low-battery notifications at **20% and 10%**, so you know when to plug it in.

Keeping the keyboard awake may use more battery. We haven't measured the battery-life difference. For people who would rather charge more often than wait for their keyboard to wake up, that can be a worthwhile tradeoff. The battery indicator and warnings make that choice easier to live with. You can turn auto-sleep back ON whenever you prefer.

This was built and tested for the **original non-backlit K2-M1**. We don't know whether other Keychron models have the same wake delay or missing battery display, and this release does not claim to fix them. See the exact compatibility below.

## What it does

- Shows the keyboard's reported battery percentage in the menu bar.
- Warns at 20% and 10% when notifications are allowed and the app is running.
- Reads the actual auto-sleep setting and lets you switch it ON or OFF.
- Keeps sleep controls in the dropdown, without taking extra menu-bar space.

Independent community project. Not affiliated with or endorsed by Keychron.

## Download and install

**[Download the preview installer](https://github.com/wretchedworm/keychron-menu/releases/tag/v1.1.0-preview.1)**

Requires an **Apple silicon Mac** running **macOS 13 or later**. The preview is **not notarized by Apple**. macOS may block its first launch. Read the [installation guide](docs/INSTALL.md) before installing.

1. Download and open `KeychronMenu-1.1.0-preview.1-arm64.dmg`.
2. Drag **KeychronMenu** onto **Applications** inside the disk image.
3. Open **KeychronMenu** from Applications. Look for its icon in the menu bar.
4. Allow notifications for battery warnings. If keyboard access is denied, use the app's **Keyboard access settings…** menu item and enable it in Input Monitoring.

No Terminal commands are needed to install the download.

## Compatibility

| Component | Verified support |
|---|---|
| Mac | Apple silicon; macOS 13+ deployment target |
| Keyboard | One original non-backlit Keychron K2-M1 |
| Connection | Bluetooth |
| Bluetooth firmware | 1.08, build date 20210820 |
| Auto-sleep | Direct state read and persistent ON/OFF control |

Other K2 revisions, K2 Pro/Max/HE models and other firmware versions are **not verified**. The sleep controller refuses unexpected firmware or memory layouts. Intel Macs and Windows are not supported by this release. The macOS 13 minimum is a build target; hardware testing was performed on the developer's Mac, not every supported OS version.

## How the switch behaves

**ON** lets the keyboard use its own auto-sleep behavior. **OFF** disables that setting. The app reads the real firmware flag instead of remembering shortcut presses or guessing from idle tests.

Applying a change briefly restarts and reconnects the keyboard. Wait for the switch to finish before typing. The app shows success only after reading back the live and saved setting. A failed or disconnected read shows **Unavailable**. Requesting the state already active avoids another write or restart.

The setting is saved in the keyboard. It was verified across keyboard restarts and read again after app restarts. The app's **Launch at login** option is separate.

## Privacy and permissions

There is no account, analytics or network service. Battery and sleep commands go directly to the connected keyboard. The sleep helper only handles the private version-response report; it does not store ordinary keystrokes. macOS may still require Input Monitoring for HID access. See [permissions and troubleshooting](docs/INSTALL.md).

## Build from source

Install Xcode with Swift 6 support, then run:

```sh
git clone https://github.com/wretchedworm/keychron-menu.git
cd keychron-menu
zsh test.sh
KEYCHRON_SIGNING_IDENTITY=- zsh build.sh
```

The app is created at `build/KeychronMenu.app`. This produces an ad-hoc signed build, not a notarized public app. A local build can use a valid Apple Development identity when one is available. Rebuilding with a different signing identity can require a fresh Input Monitoring grant.

To make the preview installer:

```sh
zsh scripts/package-dmg.sh
```

The normal tests run offline and do not change keyboard settings. [Verification](docs/VERIFICATION.md) describes the live hardware tests separately. [Protocol notes](docs/PROTOCOL.md) explain the narrowly supported sleep control.

## Reverse-engineered with REA

The K2's sleep setting wasn't available through a normal macOS control. We used **[REA — Reverse Engineer Anything](https://github.com/morluto/rea)** with Ghidra to examine the keyboard's installed Bluetooth firmware and trace how its physical sleep shortcut works.

That investigation found a way to read the real setting and change the same saved byte through the keyboard's existing Bluetooth maintenance protocol. The result is a real ON/OFF control, verified by reading the setting back after the keyboard reconnects. It does not require replacement firmware.

Credit to **[morluto/rea](https://github.com/morluto/rea)** for the reverse-engineering tools that helped make this possible. REA and Ghidra were used during development; you don't need either to use the app. The [protocol notes](docs/PROTOCOL.md) and [verification notes](docs/VERIFICATION.md) explain what was established and what remains untested.

## License

Original project code is MIT licensed. The supplied Keychron artwork and firmware-identification byte sequences are excluded from that grant; see [third-party notices](THIRD_PARTY_NOTICES.md).
