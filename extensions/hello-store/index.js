import { Store, runStoreExtension } from "@vehla/store-sdk";

runStoreExtension(async ({ commandID, query, context }) => {
  if (commandID === "copy") {
    const text =
      query ||
      context.selectedText ||
      context.clipboardText ||
      "Hello from Vehla Store";
    return Store.copyText(text);
  }

  if (commandID === "greet") {
    const subject =
      query ||
      context.selectedText ||
      context.clipboardText ||
      "there";
    return Store.showMessage(`Hello, ${subject}!`);
  }

  throw new Error(`Unknown command: ${commandID}`);
});
