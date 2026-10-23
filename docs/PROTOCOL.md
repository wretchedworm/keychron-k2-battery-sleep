# Supported sleep-control protocol

This documents the exact original K2-M1 Bluetooth firmware 1.08 dated 20210820. Addresses are firmware-specific, not a public cross-model API.

The physical Fn+S+O handler switches a byte at RAM address `0x20a359` between `0x55` (ON) and `0xaa` (OFF). It saves the byte at offset `0xbf` within the configured persistent region. On the tested device the base is `0x7e00`, so the saved setting is at EEPROM address `0x7ebf`.

Feature reports `0x71` and `0x72` provide setup/read operations. The app validates the firmware version and relevant code fingerprint before interpreting the live byte. Responses must match the requested address, length and checksum.

Changing the setting requires verified EEPROM storage mode and the original maintenance handler layout. The helper checks code fingerprints, storage base and bounds, device method pointers, report IDs, watchdog configuration, callback state and agreement between the saved and live sleep values. It refuses a mismatched configuration.

The helper then enables the existing maintenance protocol, writes exactly one setting byte, verifies the surrounding bytes, and requests a normal keyboard restart. It reconnects only to the same physical serial number and verifies the desired live and saved state. There is no injected code, firmware replacement, blanket erase or automatic write retry.

A reset can interrupt its own acknowledgement. Consequently, a successful write request alone is never treated as a completed change. Fresh post-reconnect readback is required.

The private read cursor is protected by a cross-process lock. The app also serializes battery and sleep requests. Its five-minute battery timer does not add private sleep queries.

Background research used [Infineon's HID firmware-update protocol documentation](https://www.infineon.com/assets/row/public/documents/30/42/infineon-an214821-upgrading-human-interface-device-firmware-example-protocol-commands-and-scripts-applicationnotes-en.pdf) and local analysis of the tested device. The actual write routing was verified independently; read-address routing alone does not establish where a write goes.
