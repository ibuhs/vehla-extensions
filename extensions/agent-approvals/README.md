# Agent Approvals (Notch)

Monitor Claude Code agents and approve permission requests from the Notch.

- **Closed Notch:** a pending request shows as a live activity with **Approve** / **Deny** buttons;
  a finished agent shows a short "finished" activity.
- **Tab:** pending requests (with a risk rating), live sessions, and recent decisions.
  High-risk commands (`rm -rf`, `sudo`, force-push, `curl | sh`, edits to `~/.ssh`, ...) can never be
  "always allowed".

## How it works
Claude Code hooks run `~/.vehla/agent-approvals/hook.py`, which relays the hook payload over a private
Unix socket (`0600`, in a `0700` folder) to this extension and prints the answer. If the Notch is off,
the extension isn't running, or you don't answer within ~95s, the script prints nothing and Claude
Code falls back to its normal prompt. Nothing is ever approved by default.

## Setup
Open the tab's gear: **Install** the script, then **Copy settings** and merge the `hooks` block into
`~/.claude/settings.json` (it is never edited for you). The extension loads at Notch start
(`background: true`) so it can listen while the Notch is closed.

## Develop
`swift test` runs the protocol, risk and session tests plus a real hook-script round trip.
`./build.sh` builds `dist/Agent Approvals`.
