# Install Keychron Menu

## Before you start

This preview is for Apple silicon Macs and the original non-backlit K2-M1 with Bluetooth firmware 1.08 dated 20210820. It is not a universal Keychron utility.

The download is ad-hoc signed and **not notarized by Apple**. Its first launch may be blocked. This preview does not yet provide the normal trusted first-launch experience of a Developer ID-signed, notarized app.

## Install

1. Download the `.dmg` file from this project's GitHub Releases page.
2. Double-click it to open the installer disk image.
3. Drag **KeychronMenu** onto **Applications**.
4. Open **Applications**, then double-click **KeychronMenu**.
5. Find the Keychron icon at the top of your screen. This is a menu-bar app, so it does not open a normal main window.
6. Eject the installer disk image when finished.

If macOS blocks the app, follow [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/102445). After trying to open it, go to **System Settings → Privacy & Security** and look for **Open Anyway** for KeychronMenu. Use this only if you trust this download. Do not disable Gatekeeper globally or run commands to remove security protections.

## Allow keyboard access

If the app says **macOS denied keyboard access**:

1. Click **Keyboard access settings…** in its menu.
2. Enable **KeychronMenu** under **Input Monitoring**.
3. Accept **Quit & Reopen** if macOS asks. Otherwise quit and reopen KeychronMenu yourself.

If it is missing from the list, use the plus button to add KeychronMenu from Applications. This permission lets the app access the keyboard's hardware reports. The app does not record ordinary typing.

## Allow battery warnings

Allow notifications when asked. You can change this later using **Notification settings…** in the app. Low-battery warnings happen at 20% and 10%, without repeatedly warning at the same low level.

## Use auto-sleep

Connect the keyboard over Bluetooth, then open the menu. The **Auto-sleep** switch shows the actual state read from the keyboard.

Changing it briefly reconnects the keyboard. Wait until ON or OFF appears. The app disables its switch and Quit action while a change is being verified. If it says **Change not confirmed**, choose Refresh before trying again. A failed change is never automatically repeated.

If the firmware is unsupported, the sleep control stays unavailable. Do not change the firmware solely to make this preview work.

## Update or uninstall

Quit KeychronMenu before replacing it with a newer copy. If macOS rejects an old keyboard-access grant after an update, remove its Input Monitoring entry, add the current app from Applications, and enable it again.

To uninstall, turn off **Launch at login**, quit the app, and move it from Applications to the Trash. Its saved sleep setting remains in the keyboard. Set the desired ON/OFF state before uninstalling.
