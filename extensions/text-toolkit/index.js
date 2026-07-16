import { randomUUID } from "node:crypto";
import { Store, runStoreExtension } from "@vehla/store-sdk";

function inputFor(invocation) {
  return (
    invocation.query ||
    invocation.context.selectedText ||
    invocation.context.clipboardText ||
    ""
  ).trim();
}

function requireInput(invocation, purpose) {
  const input = inputFor(invocation);
  if (!input) {
    throw new Error(`Provide text in the palette, select text, or copy text before ${purpose}.`);
  }
  return input;
}

function slugify(value) {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function convertTimestamp(value) {
  if (/^-?\d+(?:\.\d+)?$/.test(value)) {
    const numeric = Number(value);
    const milliseconds = Math.abs(numeric) >= 100_000_000_000
      ? numeric
      : numeric * 1_000;
    const date = new Date(milliseconds);
    if (Number.isNaN(date.getTime())) {
      throw new Error("The timestamp is outside the supported date range.");
    }
    return date.toISOString();
  }

  const milliseconds = Date.parse(value);
  if (Number.isNaN(milliseconds)) {
    throw new Error("Enter a Unix timestamp or a date such as 2026-07-15T21:00:00Z.");
  }
  return String(Math.floor(milliseconds / 1_000));
}

runStoreExtension(async (invocation) => {
  switch (invocation.commandID) {
    case "format-json": {
      const input = requireInput(invocation, "formatting JSON");
      try {
        return Store.copyText(JSON.stringify(JSON.parse(input), null, 2));
      } catch (error) {
        throw new Error(
          `Invalid JSON: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }

    case "slugify":
      return Store.copyText(slugify(requireInput(invocation, "creating a slug")));

    case "encode-url":
      return Store.copyText(
        encodeURIComponent(requireInput(invocation, "encoding a URL value")),
      );

    case "decode-url":
      try {
        return Store.copyText(
          decodeURIComponent(requireInput(invocation, "decoding a URL value")),
        );
      } catch {
        throw new Error("The input is not valid percent-encoded text.");
      }

    case "uuid":
      return Store.copyText(randomUUID());

    case "timestamp":
      return Store.copyText(
        convertTimestamp(requireInput(invocation, "converting a timestamp")),
      );

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
