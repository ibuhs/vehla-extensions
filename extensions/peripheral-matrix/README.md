# Peripheral Matrix

Native Vehla dock widget for wireless device batteries and live layer switching
on compatible QMK keyboards, with compact, inline, and popup surfaces. Requires
macOS 14.2+, Apple silicon, Swift 6, and the adjacent Vehla Swift SDK.

## Build and install

```sh
cd extensions/peripheral-matrix
./build.sh
swift test
swift run --package-path ../../sdk/swift vehla-swift validate dist/PeripheralMatrix
```

Install `dist/PeripheralMatrix` through Vehla’s Store and enable its Dock widget.
The build produces an ad-hoc signed bundle for local use; publication is separate.

## Battery support

Read-only IOKit discovery reads published wireless HID `BatteryPercent` values.
Missing or out-of-range values remain unknown. Opt-in Bluetooth discovery reads
Battery Service `180F` / Battery Level `2A19` and subscribes to notifications.
It queries connected peripherals by service and scans devices advertising that
service. Devices that do not advertise the Battery Service may not be found.
Matching HID and BLE entries with a unique device name are combined, preserving
the mouse/keyboard type and using the available battery reading. Ambiguous names
remain separate. Generic battery sources use a battery icon. Connected AirPods
and headphones are read from macOS’s Bluetooth report, including separate earbud
and case percentages when published. That report runs off the UI thread, is
cached for 60 seconds, and has an eight-second timeout. Unavailable readings
remain Unknown. Disconnects remove BLE entries and registry polling drops
removed HID services.

**Vehla’s app Info.plist** must declare `NSBluetoothAlwaysUsageDescription`.
A widget-local key is insufficient for an in-process extension. If the host key
is missing, the scanner displays an error instead of requesting protected access.
Allow Vehla in Privacy & Security → Bluetooth. A sandboxed host needs Bluetooth
access entitlements.

## QMK layer bridge

Enable the firmware bridge explicitly. Only QMK Raw HID endpoints (usage page
`0xFF60`, usage `0x61`) are opened without seizing input or reading keystrokes.
A valid signature/version handshake unlocks layer controls. Stock VIA/Vial
firmware does not automatically implement the included protocol.

Add `firmware/vehla_layer_bridge.c` to your QMK keymap and `SRC`, and enable
`RAW_ENABLE = yes` in `rules.mk`. Build and flash using your keyboard’s normal
QMK workflow. Keymaps must already exist in the
firmware. The live bridge labels existing layers and switches them using `layer_move`;
the bridge itself does not create macros, rewrite keymaps, or modify EEPROM.
The separate VIA editor described below can program supported keyboards. Profile labels
can be renamed and are stored in Vehla’s package data directory.

The [K10 Pro ANSI white integration](firmware/keychron-k10-pro/README.md)
preserves the current VIA mapping and macros. Its existing layers are Mac,
Mac Fn, Windows, and Windows Fn; the bridge sets the matching OS base before
enabling a Fn layer so transparent keys fall through correctly. Other keyboards
use neutral layer-number labels until renamed.

If `raw_hid_receive` already exists (including VIA), compile the bridge with
`-DVEHLA_EXISTING_RAW_HANDLER` and dispatch from the existing handler:

```c
bool vehla_raw_hid_receive(uint8_t *data, uint8_t length);
// At the beginning of the existing raw_hid_receive:
if (vehla_raw_hid_receive(data, length)) return;
```

Do not replace the existing VIA callback. Use default base layer zero for standard
Typing/IDE/Timeline switching; QMK’s combined default/active state can otherwise
keep a higher default layer active. macOS may require Input Monitoring for HID
access. Mice, headsets, and proprietary macro-profile protocols remain status-only.

32-byte reports use the following offsets (remaining bytes zero):

| Offset | Meaning |
| --- | --- |
| 0–3 | ASCII `VHLA` |
| 4 | Version `1` |
| 5 | Query `0x01`, select `0x02`; replies `0x81`, `0x82` |
| 6 | Requested layer for select; active layer for reply |
| 7 | Firmware layer count in reply |
| 8 | Reply status: `0` success, `1` invalid layer |

Only complete valid replies update state. A switch stays pending until the
keyboard reports the requested layer, times out after three seconds, and never
optimistically updates the display. State expires after ten seconds without a
reply. HID and BLE discovery stop when hidden, resume only if enabled earlier
in that widget session, and release resources on close.

## Verification

Unit tests cover battery validation and protocol signatures, versions, reply
status, malformed packets, and layer bounds. Before release on real hardware:

1. Connect/disconnect a mouse and keyboard; verify unknown values stay unknown.
2. Deny/allow Bluetooth access; read a device exposing `180F` / `2A19` and check
   notification updates and removal on disconnect.
3. Confirm stock QMK/VIA firmware cannot switch layers. With the bridge, change
   layers on the keyboard, then switch in Vehla and verify actual shortcuts.
4. Disconnect mid-switch; confirm no false success and resource cleanup on hide.

[QMK Raw HID](https://docs.qmk.fm/features/rawhid) ·
[QMK layers](https://docs.qmk.fm/feature_layers)

Registry battery scans run off the main thread at most every 30 seconds while visible.
Manual Refresh reads immediately; overlapping scans are coalesced and unchanged
results do not redraw the UI. QMK reports use asynchronous IOKit delivery;
unconfirmed firmware is probed at most three times per connection.

**Test bridge** refreshes Raw HID interfaces and retries the query-only handshake;
it does not switch layers or change the keymap. The bridge toggle, test button,
and active-layer status expose accessibility identifiers for troubleshooting.
Device callbacks use main-queue dispatch delivery and independent device
ownership so repeated replies continue during popup/menu event tracking.
With the bridged K10 Pro connected, run the optional hardware
regression test with `VEHLA_HID_INTEGRATION=1 swift test --filter LayerHardwareTests`.
It exercises the configured model's initial handshake and three Test bridge
retries during event tracking, checking that each confirmed result is published.

## LE refresh behavior

Enabling LE discovery queries already-connected Battery Service and HID devices immediately. Refresh bypasses the normal battery-read cooldown, retries missing services and characteristics, and restarts a bounded battery-service scan without toggling LE off. Disconnected devices are reconnected; stalled connection attempts are released for retry. Background discovery is throttled to once every 30 seconds, scans stop after 10 seconds, and successful battery readings normally refresh once a minute. Devices using unsupported vendor battery protocols may still report unknown.

## Devices and QMK tabs

**Devices** holds battery status, AirPods readings, and LE discovery. **QMK** holds live layer switching, profile names, bridge diagnostics, and the new keymap editor.

### Program layers

1. Connect the K10 Pro ANSI White by USB in Cable mode; close VIA/Keychron Launcher before editing.
2. In QMK, enable the firmware bridge and choose **Program layers**. Loading is read-only and captures all four firmware layers and macro storage.
3. Choose the layer to edit and click a physical key. Assign a basic key, an existing macro, a modifier shortcut, a layer action (MO/TG/TO/DF/OSL), or a 16-bit QMK keycode. Editing a layer does not change which layer is active.
4. Review draft changes and choose **Apply**. A private backup is saved before any write; only changed physical keys are written. Every write is read back, then all layers and macros are verified. Stale mappings and backup failures prevent writes. Interrupted applies attempt to restore only keys they attempted and report when restoration cannot be confirmed.

The editor supports **3434:02A3, K10 Pro ANSI White, VIA protocol 12, 6×21 matrix, four layers**. Its physical layout comes from the [official Keychron VIA definition](https://github.com/Keychron/qmk_firmware/blob/618127a725a1773e85f13455602cf6f72ab4de17/keyboards/keychron/k10_pro/via_json/k10_pro_ansi_white.json), pinned to the installed firmware source. Unsupported devices can still use the supported live bridge; the editor never guesses their matrix.

Layer tools copy existing layers, import/export `.vehla-layer.json` presets, and load a backup mapping into the draft for review. The K10 Pro's four existing layers are programmable without reflashing; increasing that count requires a firmware build. Macro contents are preserved and existing macro slots can be assigned, but this editor does not change macro sequences.

Backups live in the SDK data directory under `qmk-backups/`, with directory mode 0700 and file mode 0600. They include macro storage and should be kept private. Layer exports include key assignments only. Backups are never packaged with the extension.

Programming uses the [QMK VIA dynamic-keymap protocol](https://github.com/Keychron/qmk_firmware/blob/618127a725a1773e85f13455602cf6f72ab4de17/quantum/via.h). Firmware reset, raw EEPROM, macro-write, and flash commands are excluded. Background layer queries pause while a keymap transaction owns the connection.

Set `VEHLA_QMK_INTEGRATION=1` when running tests for a read-only native VIA check on the connected keyboard. Automated apply/rollback tests use simulated device storage and do not change a real keyboard's mappings.
