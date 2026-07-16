import dns from "node:dns/promises";
import tls from "node:tls";
import { Store, runStoreExtension } from "@vehla/store-sdk";

function inputFor(invocation) {
  return (
    invocation.query ||
    invocation.context.selectedText ||
    invocation.context.clipboardText ||
    ""
  ).trim();
}

function targetURL(invocation) {
  const input = inputFor(invocation);
  if (!input) throw new Error("Enter, select, or copy a URL.");
  const candidate = /^[a-z][a-z\d+.-]*:\/\//i.test(input) ? input : `https://${input}`;
  let url;
  try {
    url = new URL(candidate);
  } catch {
    throw new Error("Enter a valid HTTP or HTTPS URL.");
  }
  if (!["http:", "https:"].includes(url.protocol)) {
    throw new Error("Only HTTP and HTTPS URLs are supported.");
  }
  return url;
}

function requestOptions(extra = {}) {
  return {
    headers: { "User-Agent": "Vehla-Store-Web-Inspector/1.0" },
    signal: AbortSignal.timeout(12_000),
    ...extra,
  };
}

async function fetchResponse(url, options = {}) {
  let response = await fetch(url, requestOptions({ method: "HEAD", ...options }));
  if (response.status === 405 || response.status === 501) {
    response = await fetch(url, requestOptions({ method: "GET", ...options }));
  }
  return response;
}

function attributes(tag) {
  const result = {};
  for (const match of tag.matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)) {
    result[match[1].toLowerCase()] = match[2] ?? match[3] ?? match[4] ?? "";
  }
  return result;
}

function decodeEntities(value) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function extractMetadata(html, finalURL) {
  const values = {};
  const title = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]
    ?.replace(/\s+/g, " ")
    .trim();
  if (title) values.title = decodeEntities(title);

  for (const match of html.matchAll(/<meta\b[^>]*>/gi)) {
    const attrs = attributes(match[0]);
    const key = (attrs.name || attrs.property || "").toLowerCase();
    if (key && attrs.content) values[key] = decodeEntities(attrs.content.trim());
  }
  for (const match of html.matchAll(/<link\b[^>]*>/gi)) {
    const attrs = attributes(match[0]);
    if (attrs.rel?.toLowerCase().split(/\s+/).includes("canonical") && attrs.href) {
      values.canonical = new URL(attrs.href, finalURL).toString();
    }
  }
  return values;
}

async function traceRedirects(startURL) {
  const hops = [];
  let current = startURL;
  for (let index = 0; index < 10; index += 1) {
    const response = await fetch(
      current,
      requestOptions({ method: "HEAD", redirect: "manual" }),
    );
    const location = response.headers.get("location");
    hops.push({
      status: response.status,
      url: current.toString(),
      location: location ? new URL(location, current).toString() : null,
    });
    if (!location || response.status < 300 || response.status >= 400) return hops;
    current = new URL(location, current);
  }
  throw new Error("Redirect chain exceeded 10 hops.");
}

async function dnsReport(hostname) {
  const lookups = [
    ["A", () => dns.resolve4(hostname)],
    ["AAAA", () => dns.resolve6(hostname)],
    ["CNAME", () => dns.resolveCname(hostname)],
    ["MX", () => dns.resolveMx(hostname)],
    ["NS", () => dns.resolveNs(hostname)],
    ["TXT", () => dns.resolveTxt(hostname)],
  ];
  const settled = await Promise.allSettled(lookups.map(([, lookup]) => lookup()));
  const lines = [`# DNS records for ${hostname}`];
  settled.forEach((result, index) => {
    const type = lookups[index][0];
    lines.push("", `## ${type}`);
    if (result.status === "rejected") {
      lines.push("No records found.");
      return;
    }
    for (const record of result.value) {
      lines.push(
        typeof record === "string"
          ? `- ${record}`
          : `- ${JSON.stringify(record)}`,
      );
    }
  });
  return lines.join("\n");
}

function tlsReport(url) {
  if (url.protocol !== "https:") throw new Error("TLS inspection requires an HTTPS URL.");
  return new Promise((resolve, reject) => {
    const socket = tls.connect(
      {
        host: url.hostname,
        port: Number(url.port || 443),
        servername: url.hostname,
        rejectUnauthorized: false,
      },
      () => {
        const certificate = socket.getPeerCertificate(true);
        const lines = [
          `# TLS certificate for ${url.hostname}`,
          "",
          `- Authorized: ${socket.authorized}`,
          `- Authorization error: ${socket.authorizationError || "None"}`,
          `- Protocol: ${socket.getProtocol() || "Unknown"}`,
          `- Subject: ${JSON.stringify(certificate.subject || {})}`,
          `- Issuer: ${JSON.stringify(certificate.issuer || {})}`,
          `- Valid from: ${certificate.valid_from || "Unknown"}`,
          `- Valid to: ${certificate.valid_to || "Unknown"}`,
          `- SHA-256 fingerprint: ${certificate.fingerprint256 || "Unknown"}`,
          `- Serial number: ${certificate.serialNumber || "Unknown"}`,
        ];
        socket.end();
        resolve(lines.join("\n"));
      },
    );
    socket.setTimeout(12_000, () => socket.destroy(new Error("TLS connection timed out.")));
    socket.once("error", reject);
  });
}

runStoreExtension(async (invocation) => {
  const url = targetURL(invocation);

  switch (invocation.commandID) {
    case "status": {
      const started = performance.now();
      const response = await fetchResponse(url, { redirect: "follow" });
      const duration = Math.round(performance.now() - started);
      return Store.copyText(
        [
          `URL: ${url}`,
          `Final URL: ${response.url}`,
          `Status: ${response.status} ${response.statusText}`,
          `Duration: ${duration} ms`,
          `Content-Type: ${response.headers.get("content-type") || "Unknown"}`,
          `Server: ${response.headers.get("server") || "Not disclosed"}`,
        ].join("\n"),
      );
    }

    case "redirects": {
      const hops = await traceRedirects(url);
      return Store.copyText(
        hops
          .map((hop, index) =>
            `${index + 1}. ${hop.status} ${hop.url}${hop.location ? `\n   → ${hop.location}` : ""}`,
          )
          .join("\n"),
      );
    }

    case "metadata": {
      const response = await fetch(url, requestOptions({ redirect: "follow" }));
      if (!response.ok) throw new Error(`HTTP ${response.status} ${response.statusText}`);
      const html = (await response.text()).slice(0, 2_000_000);
      const metadata = extractMetadata(html, response.url);
      const ordered = [
        ["Title", metadata.title],
        ["Description", metadata.description],
        ["Canonical", metadata.canonical],
        ["Open Graph title", metadata["og:title"]],
        ["Open Graph description", metadata["og:description"]],
        ["Open Graph image", metadata["og:image"]],
        ["Twitter card", metadata["twitter:card"]],
        ["Final URL", response.url],
      ];
      return Store.copyText(
        ordered
          .filter(([, value]) => value)
          .map(([label, value]) => `${label}: ${value}`)
          .join("\n"),
      );
    }

    case "headers": {
      const response = await fetchResponse(url, { redirect: "manual" });
      const headers = [...response.headers.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([name, value]) => `${name}: ${value}`);
      return Store.copyText(
        [`HTTP ${response.status} ${response.statusText}`, ...headers].join("\n"),
      );
    }

    case "dns":
      return Store.copyText(await dnsReport(url.hostname));

    case "tls":
      return Store.copyText(await tlsReport(url));

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
