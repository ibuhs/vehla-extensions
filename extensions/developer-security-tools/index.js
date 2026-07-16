import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
} from "node:crypto";
import { Store, runStoreExtension } from "@vehla/store-sdk";

function inputFor(invocation) {
  if (invocation.query) return invocation.query;
  if (invocation.context.selectedText) return invocation.context.selectedText;
  return invocation.context.clipboardText || "";
}

function requireInput(invocation, purpose) {
  const input = inputFor(invocation);
  if (!input) throw new Error(`Enter, select, or copy text before ${purpose}.`);
  return input;
}

function hash(algorithm, value) {
  return createHash(algorithm).update(value, "utf8").digest("hex");
}

function decodeBase64URL(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return Buffer.from(padded, "base64").toString("utf8");
}

function decodeJWT(value) {
  const segments = value.trim().split(".");
  if (segments.length !== 3) throw new Error("A JWT must contain header, payload, and signature segments.");
  let header;
  let payload;
  try {
    header = JSON.parse(decodeBase64URL(segments[0]));
    payload = JSON.parse(decodeBase64URL(segments[1]));
  } catch (error) {
    throw new Error(`Invalid JWT JSON: ${error instanceof Error ? error.message : error}`);
  }
  const report = {
    warning: "Decoded only. The signature has not been verified.",
    header,
    payload,
    signature: segments[2],
  };
  for (const claim of ["iat", "nbf", "exp"]) {
    if (typeof payload[claim] === "number") {
      report[`${claim}Date`] = new Date(payload[claim] * 1_000).toISOString();
    }
  }
  if (typeof payload.exp === "number") {
    report.expired = Date.now() >= payload.exp * 1_000;
  }
  return JSON.stringify(report, null, 2);
}

function boundedInteger(value, fallback, minimum, maximum, label) {
  const text = value.trim();
  if (!text) return fallback;
  const number = Number(text);
  if (!Number.isInteger(number) || number < minimum || number > maximum) {
    throw new Error(`${label} must be a whole number from ${minimum} to ${maximum}.`);
  }
  return number;
}

function securePassword(length) {
  const groups = [
    "ABCDEFGHJKLMNPQRSTUVWXYZ",
    "abcdefghijkmnopqrstuvwxyz",
    "23456789",
    "!@#$%^&*()-_=+[]{}",
  ];
  const characters = groups.flatMap((group) => [group[randomInt(group.length)]]);
  const alphabet = groups.join("");
  while (characters.length < length) {
    characters.push(alphabet[randomInt(alphabet.length)]);
  }
  for (let index = characters.length - 1; index > 0; index -= 1) {
    const swap = randomInt(index + 1);
    [characters[index], characters[swap]] = [characters[swap], characters[index]];
  }
  return characters.join("");
}

runStoreExtension(async (invocation) => {
  switch (invocation.commandID) {
    case "sha256":
      return Store.copyText(hash("sha256", requireInput(invocation, "hashing")));

    case "sha512":
      return Store.copyText(hash("sha512", requireInput(invocation, "hashing")));

    case "base64-encode":
      return Store.copyText(
        Buffer.from(requireInput(invocation, "encoding"), "utf8").toString("base64"),
      );

    case "base64-decode": {
      const value = requireInput(invocation, "decoding").trim();
      if (!/^[A-Za-z0-9+/_-]*={0,2}$/.test(value)) {
        throw new Error("The input contains characters that are not valid Base64.");
      }
      return Store.copyText(
        value.includes("-") || value.includes("_")
          ? decodeBase64URL(value)
          : Buffer.from(value, "base64").toString("utf8"),
      );
    }

    case "jwt-decode":
      return Store.copyText(decodeJWT(requireInput(invocation, "decoding a JWT")));

    case "password": {
      const length = boundedInteger(invocation.query, 24, 12, 128, "Password length");
      return Store.copyText(securePassword(length));
    }

    case "token": {
      const bytes = boundedInteger(invocation.query, 32, 8, 128, "Token byte length");
      return Store.copyText(randomBytes(bytes).toString("base64url"));
    }

    case "hmac": {
      const [secret, ...messageParts] = requireInput(
        invocation,
        "creating an HMAC",
      ).split("|");
      const message = messageParts.join("|");
      if (!secret?.trim() || !message) {
        throw new Error("Use secret | message. Avoid entering production secrets in example extensions.");
      }
      return Store.copyText(
        createHmac("sha256", secret.trim()).update(message.trim(), "utf8").digest("hex"),
      );
    }

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
