# Focus Timer

A palette extension (Node, Store API 4) that shows a live activity in the Notch.

- **Start Focus Timer**: type the minutes (25 when empty). A countdown appears in
  the closed Notch with **+5** and **Stop** buttons.
- **Stop Focus Timer**: takes it away.

It shows how any extension can use the Notch without running inside Vehla: the
command answers with `Store.notchActivity(id, {...})` and exits. Vehla draws
the activity from that data, and its buttons run this package's own commands.

The activity's id is declared in `extension.json` under `notch.activities`,
which needs `"apiVersion": 4`.
