import { Store, runStoreExtension } from "@vehla/store-sdk";

const delays = new Map([
  ["threeSeconds", 3],
  ["fiveSeconds", 5],
  ["tenSeconds", 10],
]);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function requiredString(value, label) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} is required.`);
  }
  return value.trim();
}

runStoreExtension(async (invocation) => {
  switch (invocation.commandID) {
    case "notify-now":
      return Store.notify(
        "Vehla notification test",
        "Immediate notification delivery is working.",
      );

    case "notify-delayed": {
      const values = invocation.context.formValues;
      if (!values) {
        throw new Error(
          "This command requires a Vehla version that supports declarative forms.",
        );
      }

      const delay = delays.get(values.delay);
      if (!delay) {
        throw new Error("Choose a supported notification delay.");
      }

      const title = requiredString(values.title, "Title");
      const body = requiredString(values.body, "Message");
      await sleep(delay * 1_000);
      return Store.notify(title, body);
    }

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
