# Web Inspector

Inspect websites, APIs, DNS records, redirects, response headers, metadata, and TLS certificates from Vehla.

This extension demonstrates several Node.js networking APIs:

- Built-in `fetch`
- `AbortSignal.timeout`
- `node:dns/promises`
- `node:tls`
- Manual redirect handling
- HEAD requests with GET fallback
- Bounded HTML processing
- Concurrent DNS lookups

## Install

Install **Web Inspector** from Settings → Store.

For local development:

```sh
npm --prefix extensions/web-inspector install --install-links
```

Then install `extensions/web-inspector` as a local package.

## Input behavior

URL input is resolved in this order:

1. Explicit palette query.
2. Selected text.
3. Clipboard text.

If the input has no scheme, `https://` is added automatically:

```text
httpstatus example.com
```

Only HTTP and HTTPS URLs are accepted.

All reports are copied to the clipboard.

## Commands

### Check URL Status

Keyword: `httpstatus`

```text
httpstatus https://example.com
```

Report fields:

- Requested URL
- Final URL after redirects
- HTTP status and reason
- Request duration
- Content type
- Server header, when disclosed

The command attempts a HEAD request first. If the server returns 405 or 501, it retries with GET.

### Trace URL Redirects

Keyword: `redirects`

```text
redirects https://github.com
```

Result example:

```text
1. 301 https://example.com/
   → https://www.example.com/
2. 200 https://www.example.com/
```

Redirects are followed manually so each hop can be recorded. Relative `Location` headers are resolved against the current URL. Chains are limited to 10 hops.

### Extract Page Metadata

Keyword: `metadata`

```text
metadata https://example.com
```

The copied report can include:

- HTML title
- Meta description
- Canonical URL
- Open Graph title
- Open Graph description
- Open Graph image
- Twitter card type
- Final URL

The extension processes at most the first 2,000,000 characters of the response.

Metadata extraction intentionally uses lightweight regular expressions and attribute parsing for educational purposes. It is not a complete HTML parser.

### Inspect Response Headers

Keyword: `headers`

```text
headers https://example.com
```

Result: the HTTP status followed by alphabetically sorted response headers.

Redirects are not followed, making this useful for inspecting the first response and its `Location`, cache, security, and server headers.

### Inspect DNS Records

Keyword: `dns`

```text
dns example.com
dns https://example.com/path
```

The hostname is extracted from the URL. The extension resolves these record types concurrently:

- A
- AAAA
- CNAME
- MX
- NS
- TXT

Missing record types are reported as `No records found` without failing the entire command.

### Inspect TLS Certificate

Keywords: `tls`, `certificate`

```text
tls https://example.com
certificate example.com
```

Report fields:

- Whether Node considers the connection authorized
- Authorization error
- Negotiated TLS protocol
- Certificate subject
- Certificate issuer
- Validity dates
- SHA-256 fingerprint
- Serial number

TLS inspection requires HTTPS.

The socket uses `rejectUnauthorized: false` so the command can inspect and report invalid or self-signed certificates. The `Authorized` field must be checked before trusting the result.

## Permissions

- `clipboardRead` — permits clipboard URL fallback.
- `clipboardWrite` — copies reports.
- `selectedText` — permits selected URL fallback.
- `networkAccess` — allows outbound HTTP, DNS, and TLS operations.

No data is persisted.

## Timeouts and limits

- HTTP requests use a 12-second abort timeout.
- TLS sockets use a 12-second timeout.
- Redirect tracing stops after 10 hops.
- Metadata processing is bounded to 2 million characters.
- Vehla independently enforces its command process timeout and 1 MB protocol output limit.

Because Vehla’s overall command limit is close to the extension timeout, slow hosts may be terminated before the extension formats its own timeout error.

## Security and privacy

Invoking a command contacts the target host and may disclose:

- Your IP address.
- The extension’s `User-Agent`.
- Normal DNS resolver metadata.

Do not inspect sensitive internal hosts unless you trust the extension and understand that JavaScript packages currently run under your macOS user account.

TLS output is diagnostic, not a substitute for a complete certificate or vulnerability scanner.

## Test outside Vehla

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"status-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.web-inspector","commandID":"status","query":"https://example.com","context":{}}}' \
  | node extensions/web-inspector/index.js
```

DNS test:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"dns-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.web-inspector","commandID":"dns","query":"example.com","context":{}}}' \
  | node extensions/web-inspector/index.js
```

## Limitations

- HEAD responses can differ from GET responses.
- Metadata regexes do not execute JavaScript or render client-side pages.
- Certificate chains are not fully printed or validated beyond Node’s connection status.
- DNS output depends on the Mac’s configured resolver.
- Redirect tracing does not retry HEAD with GET.

For advanced extension authoring guidance, see the repository-level README.
