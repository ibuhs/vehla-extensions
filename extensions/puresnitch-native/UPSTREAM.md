# PureSnitch provenance

Based on [momenbasel/puresnitch](https://github.com/momenbasel/puresnitch), upstream
version 0.2.1, commit `4bfb6caffbc2736f8fc4d6c89698db5be1c8fc42`.
Copyright © 2026 Moamen Basel; MIT licensed. The full notice is in LICENSE and
is copied into the workspace bundle, companion app, and distributable package.

The SwiftUI views, models, SQLite store, rule matcher, DNS proxy, blocklist
manager, network monitor, PF manager, helper security policy, and recovery logic
derive from upstream. The Vehla adapter replaces the standalone app and menu
bar with one native workspace and inline DNS approval cards. It adds a companion
app for SMAppService registration, scopes UI preferences to this extension, and
uses separate launchd service names, root storage, and PF anchors/tokens. The
non-shipping Network Extension, app-group bridge, geolocation client, upstream
Homebrew tooling, and standalone window/menu-bar code are excluded.

Port version 1.0.0 is independent of Vehla and upstream version numbers. Upstream
engine tests are retained with their namespace expectations adapted; source
checks tied to upstream's standalone installer/Homebrew distribution are replaced
by tests for this port's actual companion and native-workspace integration.

The port also wires the helper's stored blocklists/profiles and DoH endpoint to
Settings, preserves the endpoint across helper restarts, and displays actual
socket endpoints below the retained map (which has no live geolocation).
