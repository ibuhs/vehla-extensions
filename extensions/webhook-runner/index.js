import fs from "node:fs/promises";
import path from "node:path";
import { Store, runStoreExtension } from "@vehla/store-sdk";

function inputFor(invocation) {
  return (
    invocation.query ||
    invocation.context.selectedText ||
    invocation.context.clipboardText ||
    ""
  ).trim();
}

function requireInput(invocation, example) {
  const input = inputFor(invocation);
  if (!input) throw new Error(`Input required. Example: ${example}`);
  return input;
}

function split(value) {
  return value.split("|").map((part) => part.trim());
}

function parseHeaders(value = "") {
  const headers = {};
  for (const item of value.split(";").map((part) => part.trim()).filter(Boolean)) {
    const separator = item.indexOf(":");
    if (separator <= 0) throw new Error(`Invalid header "${item}". Use Name: value.`);
    headers[item.slice(0, separator).trim()] = item.slice(separator + 1).trim();
  }
  return headers;
}

function parseRequest(value) {
  const [methodAndURL, body = "", rawHeaders = ""] = split(value);
  const match = methodAndURL.match(/^([A-Za-z]+)\s+(\S+)$/);
  if (!match) throw new Error("Start with METHOD URL, such as POST https://example.com/hook.");
  return requestFromParts(match[1], match[2], body, rawHeaders);
}

function requestFromParts(methodValue, urlValue, body = "", rawHeaders = "") {
  const method = String(methodValue).toUpperCase();
  if (!["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].includes(method)) {
    throw new Error(`Unsupported HTTP method: ${method}`);
  }
  let url;
  try {
    url = new URL(urlValue);
  } catch {
    throw new Error("Enter a valid webhook URL.");
  }
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error("Only HTTP and HTTPS webhook URLs are supported.");
  }
  const headers = parseHeaders(rawHeaders);
  if (body && !Object.keys(headers).some((name) => name.toLowerCase() === "content-type")) {
    headers["Content-Type"] = "application/json";
  }
  if (body && headers["Content-Type"]?.includes("application/json")) {
    try {
      JSON.parse(body);
    } catch (error) {
      throw new Error(`Invalid JSON body: ${error instanceof Error ? error.message : error}`);
    }
  }
  return { method, url: url.toString(), body: body || null, headers };
}

function dataFile(invocation) {
  const directory = invocation.context.dataDirectory;
  if (!directory) throw new Error("Persistent storage permission is required.");
  return path.join(directory, "webhooks.json");
}

async function loadSaved(invocation) {
  try {
    return JSON.parse(await fs.readFile(dataFile(invocation), "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return {};
    throw error;
  }
}

async function saveAll(invocation, webhooks) {
  const file = dataFile(invocation);
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.tmp`;
  await fs.writeFile(temporary, JSON.stringify(webhooks, null, 2), "utf8");
  await fs.rename(temporary, file);
}

async function send(request, authorizationHeader) {
  const headers = {
    "User-Agent": "Vehla-Store-Webhook-Runner/1.1",
    ...request.headers,
  };
  if (
    authorizationHeader &&
    !Object.keys(headers).some((name) => name.toLowerCase() === "authorization")
  ) {
    headers.Authorization = authorizationHeader;
  }

  const started = performance.now();
  const response = await fetch(request.url, {
    method: request.method,
    headers,
    body: ["GET", "HEAD"].includes(request.method) ? undefined : request.body,
    redirect: "follow",
    signal: AbortSignal.timeout(15_000),
  });
  const duration = Math.round(performance.now() - started);
  const responseBody = request.method === "HEAD" ? "" : await response.text();
  const displayBody = responseBody.length > 100_000
    ? `${responseBody.slice(0, 100_000)}\n\n[Truncated at 100 KB]`
    : responseBody;
  const safeBody = authorizationHeader
    ? displayBody.replaceAll(authorizationHeader, "<redacted>")
    : displayBody;
  const report = [
    `${request.method} ${request.url}`,
    `Status: ${response.status} ${response.statusText}`,
    `Duration: ${duration} ms`,
    `Final URL: ${response.url}`,
    `Content-Type: ${response.headers.get("content-type") || "Unknown"}`,
    "",
    safeBody,
  ].join("\n");
  return {
    report,
    status: response.status,
    statusText: response.statusText,
    duration,
    finalURL: response.url,
    contentType: response.headers.get("content-type") || "Unknown",
    body: safeBody,
  };
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function curlCommand(request) {
  const pieces = ["curl", "-i", "-X", request.method, shellQuote(request.url)];
  for (const [name, value] of Object.entries(request.headers)) {
    pieces.push("-H", shellQuote(`${name}: ${value}`));
  }
  if (request.body) pieces.push("--data-raw", shellQuote(request.body));
  return pieces.join(" ");
}

runStoreExtension(async (invocation) => {
  switch (invocation.commandID) {
    case "compose": {
      const values = invocation.context.formValues;
      if (!values) {
        throw new Error("Compose Webhook Request requires a newer version of Vehla.");
      }
      const request = requestFromParts(
        values.method,
        values.url,
        values.body,
        values.headers,
      );
      const oneTimeAuthorization = String(values.oneTimeAuthorization || "").trim();
      const storedAuthorization = values.useStoredAuthorization
        ? invocation.context.secrets?.authorizationHeader
        : undefined;
      const response = await send(
        request,
        oneTimeAuthorization || storedAuthorization,
      );
      return Store.view({
        title: `${request.method} request completed`,
        subtitle: request.url,
        sections: [
          {
            title: "Request",
            items: [
              { type: "detail", label: "Method", value: request.method },
              { type: "detail", label: "URL", value: request.url },
              {
                type: "detail",
                label: "Authorization",
                value: oneTimeAuthorization
                  ? "One-time override"
                  : storedAuthorization
                    ? "Configured secret"
                    : "Not used",
              },
            ],
          },
          {
            title: "Response",
            items: [
              {
                type: "detail",
                label: "Status",
                value: `${response.status} ${response.statusText}`,
              },
              {
                type: "detail",
                label: "Duration",
                value: `${response.duration} ms`,
              },
              {
                type: "detail",
                label: "Content-Type",
                value: response.contentType,
              },
              {
                type: "code",
                language: "text",
                text: response.body || "(Empty response body)",
              },
            ],
          },
        ],
        actions: [
          {
            type: "copyText",
            value: response.report,
            label: "Copy Report",
            systemImage: "doc.on.doc",
          },
        ],
      });
    }

    case "send": {
      const request = parseRequest(
        requireInput(invocation, "webhook POST https://example.com/hook | {\"ok\":true}"),
      );
      const response = await send(
        request,
        invocation.context.secrets?.authorizationHeader,
      );
      return Store.copyText(response.report);
    }

    case "save": {
      const [name, ...requestParts] = split(
        requireInput(
          invocation,
          "webhooksave deploy | POST https://example.com/hook | {\"deploy\":true}",
        ),
      );
      if (!name || !requestParts.length) throw new Error("Include a name and request after |.");
      const saved = await loadSaved(invocation);
      saved[name.toLowerCase()] = {
        name,
        request: parseRequest(requestParts.join(" | ")),
        updatedAt: new Date().toISOString(),
      };
      await saveAll(invocation, saved);
      return Store.showMessage(`Saved webhook “${name}”.`);
    }

    case "run-saved": {
      const name = requireInput(invocation, "webhookrun deploy").toLowerCase();
      const saved = await loadSaved(invocation);
      if (!saved[name]) throw new Error(`No saved webhook named “${name}”.`);
      const response = await send(
        saved[name].request,
        invocation.context.secrets?.authorizationHeader,
      );
      return Store.copyText(response.report);
    }

    case "list": {
      const saved = Object.values(await loadSaved(invocation))
        .sort((left, right) => left.name.localeCompare(right.name));
      if (!saved.length) return Store.showMessage("No webhooks have been saved.");
      return Store.copyText(
        saved
          .map((item) => `${item.name}\n  ${item.request.method} ${item.request.url}`)
          .join("\n\n"),
      );
    }

    case "delete": {
      const name = requireInput(invocation, "webhookdelete deploy").toLowerCase();
      const saved = await loadSaved(invocation);
      if (!saved[name]) throw new Error(`No saved webhook named “${name}”.`);
      const displayName = saved[name].name;
      delete saved[name];
      await saveAll(invocation, saved);
      return Store.showMessage(`Deleted webhook “${displayName}”.`);
    }

    case "curl": {
      const request = parseRequest(
        requireInput(invocation, "webhookcurl POST https://example.com/hook | {\"ok\":true}"),
      );
      return Store.copyText(curlCommand(request));
    }

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
