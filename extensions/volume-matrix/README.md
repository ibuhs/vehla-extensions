# Volume Matrix

A native dock widget for Vehla Alpha: mounted internal/external volumes, APFS container and per-volume usage, live physical-disk read/write rates, and mount/unmount/eject controls.

- Compact: mounted user-volume count. Inline: count and total physical-disk activity.
- Popup: shared APFS container capacity, each volume's allocated bytes, mounted volumes, and connected unmounted volumes.
- Show system volumes reveals APFS helper volumes. The startup physical disk and system helper volumes have no mount/unmount/eject controls.
- Unmount keeps a connected volume available to mount again. Eject first unmounts all volumes on the external physical disk and asks macOS to eject it; reconnect may be needed afterwards. Eject asks for confirmation and never forces an unmount.
- Locked encrypted volumes can be unlocked in Disk Utility. No passwords are collected.
- Physical-device activity comes from IOKit storage-driver counters. APFS volumes on the same device share those rates; unavailable statistics are labeled rather than invented. Container free space is shown once, not summed across volumes.

Inventory scans use two read-only `diskutil` property-list queries on a background task, at most every 30 seconds plus mount/unmount notifications and manual refresh. Lightweight IOKit counters sample once a second while visible. Background work stops when hidden. Disk Arbitration handles operations asynchronously, after fresh identity and system-disk checks.

## Build and install

```sh
./extensions/volume-matrix/build.sh
```

In **Vehla Alpha → Settings → Store → Install Local Package**, choose `extensions/volume-matrix/dist/VolumeMatrix`. Enable Volume Matrix in Dock Widgets. This is an in-process native extension; Vehla requires its usual widget acknowledgement.

```sh
swift test --package-path extensions/volume-matrix
```

Tests cover APFS sharing, sealed snapshot deduplication, system protections, counter resets and device-rate deduplication. Set `VEHLA_VOLUME_INTEGRATION=1` for a read-only live inventory/activity test. Operations are tested on a disposable disk image; no real user volume is unmounted during automated tests.
