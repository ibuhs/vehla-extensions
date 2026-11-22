# Docker Containers

A Notch / Island extension (`VehlaNotchSDK`, Store API 4).

- **Docker tab** in the open Notch: every container with its image and status,
  running ones first, with Start, Stop and Restart.
- **Live activity** in the closed Notch when a container stops ("Exited with
  code 3") or turns unhealthy, with a Restart button. Clicking it opens the tab.
- **Alerts** button in the tab: Any stop, Failures only, or Off.

## How it works

It runs your own `docker` command (Docker Desktop, OrbStack, Colima and
Homebrew locations are checked), so it sees whatever your current Docker
context sees. Nothing is polled: one `docker events` process tells it when a
container starts or stops. With alerts Off that process isn't started, and it
is ended when the Notch stops or the extension is turned off. While Docker
isn't running the extension looks again every two minutes.

A container you stop from the tab isn't announced. The manifest sets
`"background": true` because the extension has to be running to notice a
container stopping.

No network access and no account: it talks only to Docker on this Mac.

## Build

```sh
./build.sh
swift test
```

Install the `dist/Docker Containers` folder from Vehla's Store, then turn it on
in Settings › Notch / Island › Extensions.
