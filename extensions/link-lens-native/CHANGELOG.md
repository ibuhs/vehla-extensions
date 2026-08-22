# Changelog

All notable changes to Link Lens are documented here.

## 1.0.0 — 2026-08-21

Initial public package identity: `com.ibuhs.vehla.link-lens`.

### Added
- QuickGlass actions for selected text: Remove Tracking, Unwrap Redirect,
  Inspect Link, Extract Links, and Check Link Safety.
- Off-main-thread URL parsing, wrapper decoding, and bounded redirect follows.
- A compact reference workspace that lists the QuickGlass actions.

### Notes
- Safety checks are local heuristics plus an optional redirect-host comparison.
  They are not a substitute for a full malware or phishing service.
- Created with AI assistance; reviewed by a human before release.
