# PureSnitch for Vehla

A native Vehla workspace based on PureSnitch 0.2.1. Monitor connections and
aggregate throughput, browse rules, view recent helper activity, and opt into
host-wide IPv4/CIDR/port blocking plus an experimental local DNS-over-HTTPS proxy.

Build on an Apple Silicon Mac with Xcode's Swift toolchain:

```sh
zsh build.sh
```

In Vehla Settings → Store → Install Local Package, choose `dist/PureSnitch`.
Accept Vehla's native workspace notice and permissions. Invoke `puresnitch`,
`networkmonitor`, or `firewall`; `networkrules` opens Rules, and
`puresnitchsettings` opens Settings.

Install Helper is an explicit action. It copies the bundled **Vehla PureSnitch
Service.app** to `~/Applications`, then registers its root daemon using
SMAppService. Approve **Vehla PureSnitch Service** in System Settings → General →
Login Items & Extensions. Opening the workspace only checks registration and
subscribes to the helper; it never installs a service or enables enforcement.
Enforcement starts off and changes only when you turn it on in Settings.

Closing the workspace stops its XPC subscription and the helper's nettop/lsof
monitoring after the last workspace disconnects. With enforcement off, the helper
exits after three seconds and launchd wakes it when PureSnitch opens again.
Enforcement stays active when enabled, so its helper remains available without
running the traffic monitor. Each view controller owns its subscription, so
replacing a view cannot disconnect its replacement. DNS approval cards appear only
while the workspace is open; unattended asks use the selected fallback mode
after the helper's timeout. No separate menu bar item or login item is added to
Vehla. The daemon starts through its own launchd registration.

Before removing/updating the service: turn Enforcement Off, wait for both runtime
components to become inactive, then use Remove Helper or Repair Helper. Removal
requires the helper to verify cleanup. The companion app and root-owned policy
database are deliberately preserved; after removing the helper you may delete
`~/Applications/Vehla PureSnitch Service.app` in Finder. Uninstalling this Store
package alone does not unregister the macOS service or erase firewall state.
Repair Helper performs checked cleanup, unregisters, updates the companion,
and registers it again; macOS may require renewed approval.

Service names and `/Library/Application Support/Vehla PureSnitch` are separate
from upstream PureSnitch. PF uses `com.apple/vehla-puresnitch` and its own reference
token and lock. Legacy reconciliation never targets upstream's anchor or files.
The helper accepts only the configured Vehla bundle identity and its persisted
local administrator owner. Production clients must share Kaila Labs' signing
team. Local ad hoc development retains upstream's identifier and admin/owner
checks, without the production certificate chain requirement.

For a release build, set `SIGNING_IDENTITY` to Kaila Labs' Developer ID Application
identity. The build signs the helper, companion, and workspace inside out with
hardened runtime. Catalog delivery additionally needs the repository's publisher
signature and checksum. Notarize the companion/package through the release
pipeline before public distribution. The default build is ad hoc for local use.
Use the configured Developer ID identity for repeated helper updates: macOS can
retain an ad hoc helper's previous code hash and refuse to launch its replacement.
Repair refreshes the installed app's Launch Services metadata and waits for
macOS to finish unregistering the old job before registering the updated helper.
Status checks from an embedded companion copy are rejected
before accessing ServiceManagement, so tests cannot redirect a live registration.

Limitations match upstream's shipping engine: no per-app kernel filtering, live
IP geolocation, individual-connection byte totals, automatic DNS reconfiguration,
custom blocklist editor, or automatic profile switching. General rule creation,
import, and export are not implemented upstream. DNS filtering applies only to
clients explicitly pointed at the local loopback proxy. Only default-profile,
deny-only host-wide IPv4 rules become PF rules. Additional profiles are labels.

Verification:

```sh
swift test --disable-sandbox
bash Scripts/test_hardening.sh
zsh Scripts/test_loading.sh
```

Tests use temporary databases, fake PF command execution, loopback DNS sockets,
and passive installer status checks. They do not register a root daemon, change
DNS settings, or activate the real firewall. A signed local installation still
needs manual checks for Login Items approval, live nettop/lsof data, enforcement,
repair/removal, and DNS prompts. Retained upstream license: [LICENSE](LICENSE).
