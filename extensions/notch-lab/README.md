# Notch Lab

A test bench for `VehlaNotchSDK` (Store API 4, `runtime: "notch"`).

It adds one tab to the open Notch / Island with four buttons:

- **Message** shows a live activity for six seconds.
- **Countdown** shows a 30-second clock with a Copy button and a Stop button.
- **Progress** updates one activity in place (a ring from 0 to 100%) and ends it.
- **End All** ends every activity.

Close the Notch after pressing a button to see the activity. Clicking an
activity opens the Lab tab again; the last press is shown under the buttons.

## Build

```sh
./build.sh
```

Then install the `dist/Notch Lab` folder from Vehla's Store and turn the
extension on in Settings › Notch / Island › Extensions.

The manifest has `"background": false`, so Vehla loads the bundle only when the
Lab tab is first opened.
