# Set up live layer control

Key programming through VIA works without the VHLA bridge. The optional bridge adds live active-layer reporting and switching from Peripheral Matrix.

## Before you begin

The firmware installation integration has been verified only for Keychron K10 Pro ANSI White (USB 3434:02A3). Q1 Max and V-series editor profiles do not imply verified bridge firmware. Satechi SM1 does not support VIA programming. Never install another keyboard variant's firmware.

1. Identify your exact model, hardware revision, layout, backlight, firmware, and USB IDs. Check the bridge first: a confirmed live-layer reply means no installation is needed.
2. Connect directly by a data-capable USB cable in Cable/Wired mode. Close VIA/Launcher and other keyboard configuration tools. Have another way to type while the keyboard is in bootloader mode.
3. Save and verify a private backup of every layer and macro before preparing firmware. Keep a recovery path for the exact model, and original flash where readback is supported. Do not share or publish your private keymaps/macros.
4. Prepare the matching manufacturer's firmware with the included bridge integrated into the existing Raw HID/VIA handler. Preserve manufacturer functions and persistent storage. The K10 Pro scripts require their own backup format; the editor's keymap backup JSON is not interchangeable.
5. Follow the exact model's documented bootloader steps. Verify the bootloader target, application/storage boundaries, and firmware checksum before approving a flash. The widget never automatically flashes firmware.
6. After installation, reconnect and verify the VHLA handshake, VIA support, every saved mapping and macro byte, and normal keyboard behavior. Restore differences only with approval and verified readback. Return to the original layer after testing live switches.

## Use an AI assistant

Choose Copy AI setup prompt in the setup assistant and paste it into an AI tool you trust. An agent with local terminal and USB/HID access can help inspect, back up, build, and verify. A chat-only account can guide you through commands but cannot operate or verify your hardware itself. The prompt requires a separate approval before flashing and includes compatibility, privacy, and recovery checks.

Keep the included firmware/keychron-k10-pro/README.md and scripts available to the assistant. They contain the pinned source and target-specific steps. Do not reuse their memory addresses or firmware on other models.

Primary references:
- QMK Raw HID: https://docs.qmk.fm/features/rawhid
- QMK flashing and bootloaders: https://docs.qmk.fm/flashing
- Keychron firmware downloads: https://www.keychron.com/pages/firmware-and-json-files-of-the-keychron-qmk-keyboards
