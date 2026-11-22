import { Store, runStoreExtension } from "@vehla/store-sdk";

// A palette extension that shows a live activity in the Notch. Nothing keeps running: the command
// answers with the activity as data and exits, and Vehla draws the countdown.
runStoreExtension(async ({ commandID, query }) => {
  if (commandID === "stop") {
    return Store.endNotchActivity("focus");
  }

  if (commandID === "start") {
    const typed = Number.parseFloat(query);
    const minutes = Number.isFinite(typed) && typed > 0 ? Math.min(typed, 240) : 25;
    return Store.notchActivity("focus", {
      title: "Focus",
      systemImage: "timer",
      tint: "#FF9F0A",
      countdown: minutes * 60,
      // A click on the activity starts the same length again.
      command: "start",
      query: String(minutes),
      buttons: [
        { title: "+5", systemImage: "plus", command: "start", query: String(minutes + 5) },
        { title: "Stop", systemImage: "stop.fill", command: "stop" },
      ],
    });
  }

  throw new Error(`Unknown command: ${commandID}`);
});
