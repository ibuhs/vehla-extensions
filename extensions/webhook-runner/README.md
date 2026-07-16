# Webhook Runner

Send, save, inspect, and reproduce HTTP requests from Vehla’s palette.

This extension is a reference for:

- Parsing a compact command syntax.
- Sending multiple HTTP methods.
- Validating JSON bodies.
- Adding request headers.
- Following redirects.
- Truncating large responses.
- Persisting named requests.
- Atomic JSON file updates.
- Injecting a Keychain-backed authorization value at send time.
- Collecting structured input with a native declarative form.
- Presenting response metadata and bodies in a rich native result.
- Generating shell-safe cURL commands.

## Install

Install **Webhook Runner** from Settings → Store.

For local development:

```sh
npm --prefix extensions/webhook-runner install --install-links
```

Then install `extensions/webhook-runner` as a local package.

For authenticated endpoints, save the complete header value—such as `Bearer <token>`—under **Authorization Header** in the package’s Store settings.

## Request syntax

```text
METHOD URL | optional body | Header: value; Another-Header: value
```

Supported methods:

- GET
- POST
- PUT
- PATCH
- DELETE
- HEAD

The method and URL are required. The body and headers are optional.

When a body is present and no Content-Type header is supplied, the extension adds:

```text
Content-Type: application/json
```

If Content-Type contains `application/json`, the body must parse as valid JSON.

## Commands

### Compose Webhook Request

Keyword: `webhookform`

Selecting the command opens a native request builder with:

- An HTTP method picker.
- A required URL field.
- A multiline request body.
- Multiline semicolon-separated headers.
- A toggle for the configured Authorization secret.
- A secure one-time Authorization override.

Choose **Send Request** to run it. Vehla passes the submitted values through `invocation.context.formValues`. The secure override is transient, is redacted from runtime errors, and takes precedence over the configured secret.

The response opens in a native result view containing request metadata, status, duration, content type, and a selectable response body. Choose **Copy Report** to use the brokered clipboard action.

### Send Webhook

Keyword: `webhook`

GET:

```text
webhook GET https://httpbin.org/anything
```

POST JSON:

```text
webhook POST https://httpbin.org/anything | {"name":"Vehla","active":true}
```

Custom headers:

```text
webhook POST https://httpbin.org/anything | {"event":"deploy"} | X-Environment: staging; X-Source: Vehla
```

An explicit authorization header is supported:

```text
webhook POST https://example.com/hook | {"ok":true} | Authorization: Bearer TOKEN
```

For real credentials, use the Store secret instead of query text. When configured, it is injected as the `Authorization` header unless the request syntax already contains that header.

Result: a response report is copied to the clipboard:

```text
POST https://example.com/hook
Status: 200 OK
Duration: 241 ms
Final URL: https://example.com/hook
Content-Type: application/json

{"received":true}
```

Response bodies are truncated after 100 KB.

### Save Webhook

Keyword: `webhooksave`

Syntax:

```text
webhooksave NAME | METHOD URL | optional body | optional headers
```

Example:

```text
webhooksave deploy | POST https://httpbin.org/anything | {"deploy":true} | X-Environment: staging
```

Names are case-insensitive for lookup. Saving the same name again replaces its request and updates its timestamp.

Saved requests are not sent automatically.

### Run Saved Webhook

Keyword: `webhookrun`

```text
webhookrun deploy
```

The stored request is sent and its response report is copied. A configured Authorization secret is injected at send time and is not added to the saved request.

### List Saved Webhooks

Keyword: `webhooklist`

```text
webhooklist
```

Result example:

```text
deploy
  POST https://httpbin.org/anything

health
  GET https://example.com/health
```

### Delete Saved Webhook

Keyword: `webhookdelete`

```text
webhookdelete deploy
```

The extension displays a confirmation message after deletion.

### Generate cURL Command

Keyword: `webhookcurl`

```text
webhookcurl POST https://httpbin.org/anything | {"hello":"world"} | X-Source: Vehla
```

Result:

```sh
curl -i -X POST 'https://httpbin.org/anything' -H 'X-Source: Vehla' -H 'Content-Type: application/json' --data-raw '{"hello":"world"}'
```

Arguments are single-quoted for a POSIX-compatible shell, including safe handling of embedded single quotes.

Generating cURL does not send the request.

The generated command intentionally excludes the configured Authorization secret. Only headers typed directly into the request syntax appear in cURL output.

The form command also redacts a directly echoed Authorization value from the displayed response body and copied report.

## Input fallback

Request text is resolved in this order:

1. Explicit palette query.
2. Selected text.
3. Clipboard text.

For predictable behavior, use explicit query text for save, run, list, and delete workflows.

## Permissions

- `clipboardRead` — permits request syntax from the clipboard.
- `clipboardWrite` — copies response reports, saved lists, and cURL commands.
- `selectedText` — permits request syntax from selected text.
- `networkAccess` — permits sending requests.
- `persistentStorage` — supplies the directory used for `webhooks.json`.

Vehla asks for persistent storage before every command because the package declares it and Store API version 1 grants storage at package launch. Even commands that do not save data may therefore require the permission.

The package also declares one optional secret:

- `authorizationHeader` — the complete value for the HTTP `Authorization` header.

Vehla stores it in the macOS Keychain. The extension receives it for an invocation but never writes it to `webhooks.json`.

The form’s secure one-time override is not a persisted secret. Use it only when a credential should apply to one invocation.

## Persistent data

Saved definitions are stored in:

```text
<Vehla Store data directory>/com.vehla.examples.webhook-runner/webhooks.json
```

The exact parent directory is supplied by Vehla as `context.dataDirectory`.

Writes are atomic:

1. Serialize the complete record map.
2. Write a process-specific temporary file.
3. Rename the temporary file over `webhooks.json`.

Uninstalling the package removes its private data directory.

## Important security warning

Saved requests are plain JSON. Do not put these values in request syntax or saved headers:

- Production API tokens.
- Passwords.
- Private signing keys.
- Session cookies.
- Confidential payloads.

Use the Store’s Keychain-backed **Authorization Header** field instead. URLs can still contain sensitive path tokens or query parameters and are not protected by the secret store.

The extension follows redirects using `fetch`. Review target URLs carefully before injecting credentials. Keychain storage protects the value at rest; the extension process and destination server still receive it while the command runs.

## Parser limitations

The compact syntax uses:

- `|` between request sections.
- `;` between headers.
- The first `:` inside a header as the name/value separator.

Consequences:

- A JSON string containing `|` cannot be represented reliably.
- A header value containing `;` is split into multiple headers.
- Multiline bodies are awkward in the palette.

For complex bodies, extend the package to accept a single JSON configuration object or load body content from a user-selected file after the Store exposes that API.

## Test outside Vehla

Generate cURL without network access:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"curl-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.webhook-runner","commandID":"curl","query":"POST https://example.com/hook | {\"ok\":true}","context":{}}}' \
  | node extensions/webhook-runner/index.js
```

Test a live request:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"send-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.webhook-runner","commandID":"send","query":"GET https://httpbin.org/anything","context":{}}}' \
  | node extensions/webhook-runner/index.js
```

Saved-command testing requires a writable `dataDirectory`:

```sh
temporary_directory="$(mktemp -d)"
printf '%s\n' \
  "{\"jsonrpc\":\"2.0\",\"id\":\"save-test\",\"method\":\"store.invoke\",\"params\":{\"packageID\":\"com.vehla.examples.webhook-runner\",\"commandID\":\"save\",\"query\":\"health | GET https://example.com\",\"context\":{\"dataDirectory\":\"$temporary_directory\"}}}" \
  | node extensions/webhook-runner/index.js
```

Delete the temporary directory after testing.

## Production hardening ideas

- Restrict allowed destination hosts.
- Disable cross-origin forwarding of authorization headers.
- Add configurable response-size limits.
- Support JSON-based request definitions.
- Add retry policies with exponential backoff.
- Redact sensitive headers from generated reports.

For Store protocol and publishing details, see the repository-level README.
