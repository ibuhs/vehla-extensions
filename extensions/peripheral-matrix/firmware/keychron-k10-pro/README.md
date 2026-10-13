# Keychron K10 Pro ANSI white bridge

This integration targets only USB `3434:02A3`, Raw HID usage `FF60:61`.
It keeps the existing four layers (Mac, Mac Fn, Windows, Windows Fn), VIA
configuration, Bluetooth controls and factory handlers. It adds the VHLA
runtime layer protocol; no layer selections write EEPROM.

Use official [Keychron QMK source](https://github.com/Keychron/qmk_firmware)
revision `618127a725a1773e85f13455602cf6f72ab4de17` from
`bluetooth_playground`, with its pinned submodules and Arm GNU 13.3 compiler.
The later wireless_playground revision was not used for this verified build.

1. Connect the exact keyboard in Cable mode. Close VIA/Launcher.
2. Run `backup_via.py private-backups/before-vehla.json` using Python with
   `hidapi` installed. This reads twice and saves all four layers and macros.
3. Run `prepare_keymap.py /path/to/keychron-qmk private-backups/before-vehla.json`.
   It verifies the revision and generates the keymap directly from the backup.
4. Build `make keychron/k10_pro/ansi/white:vehla SKIP_GIT=yes`.
5. Enter bootloader using Keychron's documented Off → hold Esc → Cable sequence.
   Identify the single STM32 DFU device and its flash geometry before writing.
   Back up original flash into the private directory when upload is permitted.
6. Flash the generated binary to internal flash at `0x08000000` with dfu-util.
   Do not mass erase or change option bytes. This build's image is 49,756 bytes;
   its EEPROM storage begins at `0x0801E000` on the configured 128 KB MCU.
7. Run `restore_via.py private-backups/before-vehla.json`. It checks device and
   buffer geometry, writes only differences, then verifies every keymap and
   macro byte against the saved copy. Re-query the VHLA handshake and test
   switching before declaring installation successful.
8. In Vehla Alpha, enable **Connect QMK firmware bridge**. USB is required for
   layer switching; battery discovery can continue over Bluetooth separately.

The 4096-byte logical EEPROM matches the connected keyboard's existing
3050-byte macro buffer. The generated default keymap preserves current mappings
even if VIA initializes EEPROM after the firmware change; macros are restored
from the backup. Fn layers retain transparent fallthrough to their OS base.

`private-backups/` is gitignored: it contains personal keymaps/macros and firmware
compiled with those mappings. Keep these files private. No firmware is flashed
by the preparation or backup scripts.
