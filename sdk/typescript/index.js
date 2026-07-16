import { createInterface } from "node:readline";

export const Store = {
  copyText(value) {
    return { action: { type: "copyText", value } };
  },

  openURL(value) {
    return { action: { type: "openURL", value } };
  },

  showMessage(value) {
    return { action: { type: "showMessage", value } };
  },

  view(value) {
    return { view: value };
  },
};

export function runStoreExtension(handler) {
  const lines = createInterface({
    input: process.stdin,
    crlfDelay: Infinity,
    terminal: false,
  });

  lines.on("line", async (line) => {
    let request;
    try {
      request = JSON.parse(line);
      if (
        request?.jsonrpc !== "2.0" ||
        request?.method !== "store.invoke" ||
        typeof request?.id !== "string"
      ) {
        throw new Error("Unsupported Store request.");
      }

      const result = await handler(request.params);
      process.stdout.write(
        `${JSON.stringify({
          jsonrpc: "2.0",
          id: request.id,
          result: result ?? {},
        })}\n`,
      );
    } catch (error) {
      process.stdout.write(
        `${JSON.stringify({
          jsonrpc: "2.0",
          id: request?.id ?? null,
          error: {
            code: -32000,
            message: error instanceof Error ? error.message : String(error),
          },
        })}\n`,
      );
    }
  });
}
