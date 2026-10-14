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
Missing or out-of-range values remain unknown. Automatic Bluetooth discovery reads
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
reply. HID and BLE discovery stop when hidden, automatically resume Bluetooth discovery when visible again, and release resources on close.

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

Automatic LE discovery queries already-connected Battery Service and HID devices immediately. Refresh bypasses the normal battery-read cooldown, retries missing services and characteristics, and restarts a bounded battery-service scan without a discovery toggle. Disconnected devices are reconnected; stalled connection attempts are released for retry. Background discovery is throttled to once every 30 seconds, scans stop after 10 seconds, and successful battery readings normally refresh once a minute. Devices using unsupported vendor battery protocols may still report unknown.

## Battery popup and keyboard programming

The compact 440 × 400 popup holds battery status, AirPods readings, and automatic LE discovery. **QMK Keyboard Programming** at the bottom opens a separate resizable glass-style window (920 × 780) with live layer switching, profile names, bridge diagnostics, and the keymap editor. The keyboard connection stays active while this window is open, even when the dock popup closes. Layer editing and optional live activation are toolbar controls; connection diagnostics and layer naming are available in the options menu.

### Program layers

1. Connect a supported keyboard by USB in Cable mode; close VIA/Keychron Launcher before editing.
2. Open **QMK Keyboard Programming**. USB discovery is always enabled while this window is open, and the connected supported keyboard automatically loads its layout and current mapping. Loading is read-only and captures all four firmware layers and macro storage.
3. Choose the layer in the toolbar above the keyboard and click a physical key. Assign a basic key, an existing macro, a modifier shortcut, a layer action (MO/TG/TO/DF/OSL), or a 16-bit QMK keycode. Editing a layer does not change which layer is active.
4. Review draft changes and choose **Apply**. A private backup is saved before any write; only changed physical keys are written. Every write is read back, then all layers and macros are verified. Stale mappings and backup failures prevent writes. Interrupted applies attempt to restore only keys they attempted and report when restoration cannot be confirmed.

Supported layouts are matched by exact USB vendor/product IDs, never by keyboard name or size alone:

| Family | Layouts | Size |
| --- | --- | --- |
| K10 Pro White | ANSI | Full size |
| Q1 Max | ANSI, ISO, JIS knob | 75% |
| V1 | ANSI, ANSI knob | 75% |
| V2 | ANSI, ANSI knob | 65% |
| V3 | ANSI, ANSI knob | TKL |
| V4 | ANSI | 60% |
| V5 | ANSI, ANSI knob | 96% |
| V6 | ANSI, ANSI knob | Full size |

All profiles require VIA protocol 12 and four firmware layers. The K10 Pro integration was checked on physical hardware. Q1 Max and V-series profiles are definition-backed and tested against simulated storage; physical-device verification is still needed. Newer firmware reporting another protocol is rejected before writes. Knob presses are ordinary matrix keys; knob rotation, lighting, and macro sequences are preserved rather than edited.

Satechi states that [SM1 does not support VIA key mapping](https://support.satechi.com/hc/en-us/articles/57165043922971-Does-the-SM1-Slim-Mechanical-Backlit-Bluetooth-Keyboard-support-VIA-key-mapping). It remains eligible for battery/status discovery when macOS or its Bluetooth Battery Service provides readings; it is not offered a guessed QMK editor.

Layouts come from pinned public definitions: [K10 Pro source](https://github.com/Keychron/qmk_firmware/blob/618127a725a1773e85f13455602cf6f72ab4de17/keyboards/keychron/k10_pro/via_json/k10_pro_ansi_white.json), [Q1 Max source](https://github.com/Keychron/qmk_firmware/tree/666862cb8123b64a6b96718d739c6203ad99031f/keyboards/keychron/q1_max/via_json), and [VIA's Keychron V-series definitions](https://github.com/the-via/keyboards/tree/9e3e9f4aa9f50f9439fdebc747560f51aaf109a0/v3/keychron). Generated catalog entries include source URLs and definition SHA-256 hashes. `Scripts/generate_keyboard_profiles.py` regenerates the catalog from downloaded definitions without network access or hardware writes. Unsupported devices can still use supported live bridge firmware; the editor never guesses their matrix.

Layer tools copy existing layers, import/export `.vehla-layer.json` presets, and load a backup mapping into the draft for review. The K10 Pro's four existing layers are programmable without reflashing; increasing that count requires a firmware build. Macro contents are preserved and existing macro slots can be assigned, but this editor does not change macro sequences.

Backups live in the SDK data directory under `qmk-backups/`, with directory mode 0700 and file mode 0600. They include macro storage and should be kept private. Layer exports include key assignments only. Backups are never packaged with the extension.

Programming uses the [QMK VIA dynamic-keymap protocol](https://github.com/Keychron/qmk_firmware/blob/618127a725a1773e85f13455602cf6f72ab4de17/quantum/via.h). Firmware reset, raw EEPROM, macro-write, and flash commands are excluded. Background layer queries pause while a keymap transaction owns the connection.

Set `VEHLA_QMK_INTEGRATION=1` when running tests for a read-only native VIA check on the connected keyboard. Automated apply/rollback tests use simulated device storage and do not change a real keyboard's mappings.

Bluetooth warnings are scoped to battery discovery and cleared when Core Bluetooth recovers, on a powered-on refresh, or when discovery stops. A powered-off warning is shown only after the same active manager remains off for two seconds, avoiding transient startup/wake alerts. Recovery never clears unrelated QMK errors.

## Guided bridge setup and AI assistance

In Keyboard Programming, choose **Set up live layer control** beside the layer toolbar when the bridge is unavailable, or **Live layer setup and AI prompt…** in the options menu at any time. The setup assistant explains compatibility, verified backup, model-specific installation, and post-flash verification. **Copy AI setup prompt** copies a self-contained workflow for an AI tool with local hardware access, or a chat assistant guiding local commands. It does not send data to an AI service or flash firmware.

[Read the setup guide](Sources/PeripheralMatrix/Resources/bridge-setup-guide.md) · [Read the AI prompt](Sources/PeripheralMatrix/Resources/bridge-setup-ai-prompt.txt). Both are bundled offline and also included as `firmware/BRIDGE_SETUP.md` and `firmware/AI_SETUP_PROMPT.txt` in the distributable package. Bridge installation is optional for VIA programming, and firmware integration remains verified only for the K10 Pro ANSI White.

Bluetooth LE battery discovery starts automatically whenever the widget becomes visible, including after app restarts. There is no enable checkbox or saved off state. Discovery still releases resources while hidden and respects macOS Bluetooth permission and hardware availability.
