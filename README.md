# Vehla Extensions

Build command packages that add new capabilities to Vehla’s Store.

An extension can contain one command or an entire toolkit. Commands can:

- Accept palette arguments, selected text, and clipboard text.
- Perform synchronous or asynchronous JavaScript work.
- Call public or private HTTP APIs.
- read and write extension-owned persistent data.
- Copy generated output to the clipboard.
- Open HTTP and HTTPS URLs.
- Display a message.
- Report useful errors without destabilizing Vehla.

This repository contains the TypeScript/JavaScript SDK and complete example extensions.

## Current platform scope

The current Store API is optimized for command-driven extensions.

Supported:

- Multiple commands per package.
- Keyword invocation and palette discovery.
- Node.js 20 or newer.
- Asynchronous handlers.
- Clipboard and selected-text context.
- Network requests.
- Private persistent storage.
- Keychain-backed extension secrets.
- Browser handoff.
- Structured validation and errors.
- A separate process per invocation.
- A 15-second execution limit.
- A 1 MB protocol output limit.

Not yet supported:

- Custom embedded SwiftUI or web views.
- Long-running background processes.
- Scheduled commands.
- Extension-defined global hotkeys.
- A security sandbox for JavaScript.
- In-process Swift extension bundles.



## Repository layout

```text
vehla-extensions/
├── README.md
├── LICENSE
├── catalog.json
├── packages/
│   └── <self-contained versioned archives>
├── scripts/
│   └── build-catalog.py
├── sdk/
│   └── typescript/
│       ├── package.json
│       ├── index.js
│       └── index.d.ts
└── extensions/
    ├── hello-store/
    ├── text-toolkit/
    ├── github-workflow/
    ├── web-inspector/
    ├── webhook-runner/
    └── developer-security-tools/
```

## Prerequisites

- macOS with Vehla’s Store feature.
- Node.js 20 or newer.
- Basic JavaScript or TypeScript knowledge.

Confirm Node is available:

```sh
node --version
```

## Install from Vehla

Published extensions are available directly in Vehla:

1. Open Vehla Settings.
2. Select Store.
3. Choose **Refresh Catalog**.
4. Review an extension’s commands and requested capabilities.
5. Choose **Install**.
6. Set each permission to Ask, Allow, or Deny.
7. Invoke one of the displayed keywords from the palette.

When a newer catalog version is available, the Install button becomes **Update**. Updating replaces the installed package while preserving its enabled state, permission decisions, and private data.

Every catalog archive has a SHA-256 checksum. Vehla verifies the downloaded archive against `catalog.json` before extracting or installing it.

## Try a local development extension

Install its local SDK dependency:

```sh
git clone https://github.com/ibuhs/vehla-extensions.git
cd vehla-extensions
npm --prefix extensions/github-workflow install --install-links
```

Then:

1. Open Vehla Settings.
2. Select Store.
3. Choose **Install Local Package**.
4. Select `extensions/github-workflow`.
5. Review its commands and requested capabilities.
6. Enable the package.
7. Invoke `ghrepo apple/swift` from the palette.

`--install-links` is important for local SDK development. It places a self-contained SDK copy inside the extension’s `node_modules` directory. Vehla rejects symbolic links that escape an installed package.

## Create a package

Create this structure:

```text
my-extension/
├── extension.json
├── package.json
├── package-lock.json
├── index.js
└── node_modules/
```

Example `package.json` while developing inside this repository:

```json
{
  "name": "my-vehla-extension",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "dependencies": {
    "@vehla/store-sdk": "file:../../sdk/typescript"
  }
}
```

Install dependencies:

```sh
npm --prefix extensions/my-extension install --install-links
```

## Manifest reference

Every package must contain `extension.json`.

```json
{
  "apiVersion": 1,
  "id": "com.example.my-extension",
  "name": "My Extension",
  "version": "1.0.0",
  "description": "A concise user-facing description.",
  "author": "Your Name",
  "entrypoint": "index.js",
  "commands": [
    {
      "id": "hello",
      "title": "Say Hello",
      "subtitle": "Create a greeting",
      "keywords": ["hello", "greet"],
      "systemImage": "hand.wave"
    }
  ],
  "capabilities": [
    "clipboardWrite"
  ],
  "secrets": [
    {
      "id": "apiToken",
      "label": "API Token",
      "description": "Token used to authenticate API requests.",
      "required": true
    }
  ]
}
```

### Top-level fields

`apiVersion`

- Required integer.
- Must currently be `1`.
- Vehla rejects unsupported versions.

`id`

- Required stable package identifier.
- Use reverse-domain notation: `com.company.package`.
- Allowed characters are letters, numbers, `.`, `_`, and `-`.
- Must begin with a letter or number.
- Do not change it between releases; it identifies installed state and permissions.

`name`

- Required user-facing package name.

`version`

- Required version string.
- Semantic versioning is recommended.

`description`

- Optional package summary shown in Store settings.

`author`

- Optional author or organization.

`entrypoint`

- Required relative JavaScript path.
- Absolute paths and `..` path traversal are rejected.
- The resolved entrypoint must remain inside the package.

`commands`

- Required non-empty command array.
- Command IDs must be unique within the package.

`capabilities`

- Optional package capability declarations.
- Undeclared broker actions are denied.

`secrets`

- Optional declarations for credentials configured by the user in Store settings.
- Each declaration requires a unique `id` and non-empty `label`.
- `description` explains where the value comes from and how the extension uses it.
- Set `required` to `true` to prevent command execution until the value is configured.
- Declarations never contain the secret value.
- Values are stored in the macOS Keychain, scoped to the package ID, and removed when the package is uninstalled.

### Command fields

`id`

- Stable identifier unique within the package.
- Vehla namespaces it with the package ID.

`title`

- Main palette result title.

`subtitle`

- Optional one-line explanation.

`keywords`

- Optional invocation shortcuts.
- An exact keyword invokes the command with an empty query.
- Text following a keyword becomes `invocation.query`.
- Example: `ghrepo apple/swift` invokes keyword `ghrepo` with query `apple/swift`.

`systemImage`

- Optional SF Symbol name.
- Defaults to `shippingbox`.
- Use symbols available on Vehla’s macOS deployment target.

## Capabilities

Capabilities communicate intent and gate Vehla-provided context or actions.

### `clipboardRead`

Allows clipboard text to be included as `invocation.context.clipboardText`.

### `clipboardWrite`

Allows a `copyText` result action.

### `selectedText`

Allows captured frontmost-application text to be included as `invocation.context.selectedText`.

### `openURL`

Allows an `openURL` result action.

Only HTTP and HTTPS URLs are accepted by the broker.

### `networkAccess`

Requires approval before a package declaring network access is launched.

This is an intent and launch gate, not host-level network isolation. JavaScript currently runs under the user’s account.

### `persistentStorage`

Provides a private directory path in `invocation.context.dataDirectory`.

Use it for extension-owned settings, caches, and records. Vehla removes this directory when the package is uninstalled.

### `notifications`

Reserved for notification APIs. Declaring it documents intent, but a notification helper is not yet part of API version 1.

### `userSelectedFiles`

Reserved for security-scoped file selection APIs. It is not yet exposed to command handlers in API version 1.

## Permission behavior

Each requested capability has three saved states:

- **Ask:** prompt when the capability is needed.
- **Allow:** approve future uses.
- **Deny:** reject the capability.

The permission prompt supports:

- Allow Once.
- Always Allow.
- Deny.

Extensions must handle missing optional context. A user may allow clipboard access but deny selected text, or vice versa.

## Write an entrypoint

```js
import { Store, runStoreExtension } from "@vehla/store-sdk";

runStoreExtension(async (invocation) => {
  switch (invocation.commandID) {
    case "hello": {
      const subject =
        invocation.query ||
        invocation.context.selectedText ||
        invocation.context.clipboardText ||
        "there";

      return Store.copyText(`Hello, ${subject}!`);
    }

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
```

Call `runStoreExtension` exactly once. The SDK:

1. Reads newline-delimited JSON-RPC from standard input.
2. Validates the request envelope.
3. Calls your handler.
4. Writes one JSON-RPC response to standard output.
5. Converts thrown errors into protocol errors.

## Invocation object

```ts
interface StoreInvocation {
  packageID: string;
  commandID: string;
  query: string;
  context: {
    selectedText?: string;
    clipboardText?: string;
    frontmostApplication?: string;
    dataDirectory?: string;
    secrets: Readonly<Record<string, string>>;
  };
}
```

`packageID`

- The manifest package ID.

`commandID`

- The selected command’s manifest ID.

`query`

- Text after an exact keyword.
- Empty when a user selects a command by title without arguments.

`selectedText`

- Present only when text was captured and permission was granted.

`clipboardText`

- Present only when clipboard text exists and permission was granted.

`frontmostApplication`

- Best-effort application context captured by Vehla.

`dataDirectory`

- Present when persistent storage was declared and approved.

`secrets`

- Contains only values declared by the installed manifest and configured in Store settings.
- Optional unconfigured secrets are omitted.
- A command is not launched when a required secret is missing.
- Treat values as transient credentials: do not log, copy, persist, or include them in errors.

## Input precedence

Most text commands should use:

```js
function inputFor(invocation) {
  return (
    invocation.query ||
    invocation.context.selectedText ||
    invocation.context.clipboardText ||
    ""
  );
}
```

Use `query` first so explicit arguments win. Preserve whitespace for hashing, encoding, or formatting commands when whitespace is meaningful.

For generators such as passwords, read options only from `invocation.query`; do not accidentally interpret clipboard contents as configuration.

## Result actions

A handler returns a result object or nothing.

### Copy text

Requires `clipboardWrite`.

```js
return Store.copyText("Generated output");
```

Equivalent protocol result:

```json
{
  "action": {
    "type": "copyText",
    "value": "Generated output"
  }
}
```

### Open a URL

Requires `openURL`.

```js
return Store.openURL("https://example.com");
```

Only HTTP and HTTPS URLs are allowed.

### Show a message

```js
return Store.showMessage("Operation completed.");
```

Use messages for short confirmations. Prefer clipboard output for reports and substantial content.

### Message plus action

The protocol supports both fields:

```js
return {
  message: "Copied formatted JSON.",
  action: {
    type: "copyText",
    value: formatted,
  },
};
```

## Asynchronous commands

Handlers may return promises:

```js
runStoreExtension(async (invocation) => {
  const response = await fetch("https://api.example.com/data", {
    signal: AbortSignal.timeout(10_000),
  });

  if (!response.ok) {
    throw new Error(`API returned ${response.status} ${response.statusText}`);
  }

  return Store.copyText(JSON.stringify(await response.json(), null, 2));
});
```

Recommended network practices:

- Declare `networkAccess`.
- Set explicit timeouts below Vehla’s 15-second command limit.
- Check `response.ok`.
- Bound downloaded body sizes.
- Truncate large reports.
- Avoid silently following unlimited redirect chains.
- Add a descriptive `User-Agent` for public APIs.
- Explain unauthenticated API rate limits.

## Persistent storage

Declare `persistentStorage`, then use the provided directory:

```js
import fs from "node:fs/promises";
import path from "node:path";

async function saveState(invocation, state) {
  const directory = invocation.context.dataDirectory;
  if (!directory) {
    throw new Error("Persistent storage permission is required.");
  }

  await fs.mkdir(directory, { recursive: true });
  const destination = path.join(directory, "state.json");
  const temporary = `${destination}.${process.pid}.tmp`;

  await fs.writeFile(temporary, JSON.stringify(state, null, 2), "utf8");
  await fs.rename(temporary, destination);
}
```

Use atomic temporary-file replacement to reduce corruption risk.

Do not store passwords, API keys, OAuth tokens, or production webhook secrets in plain JSON. Declare them in the manifest and read them from `invocation.context.secrets`.

## Secure secrets

Declare credentials in `extension.json`:

```json
{
  "secrets": [
    {
      "id": "apiToken",
      "label": "API Token",
      "description": "Create a read-only token in the service dashboard.",
      "required": true
    }
  ]
}
```

Read the value only when handling a command:

```js
const token = invocation.context.secrets.apiToken;

const response = await fetch("https://api.example.com/v1/items", {
  headers: {
    Authorization: `Bearer ${token}`,
  },
});
```

Vehla stores configured values in the macOS Keychain, never in Store state or the extension directory. Runtime diagnostics and protocol error messages are redacted before Vehla displays them when they contain an injected value.

The extension process receives declared values for the duration of each invocation. Because JavaScript packages are not sandboxed, install only trusted source. Keychain storage protects credentials at rest; it cannot make a malicious extension safe.

Guidelines:

- Request the narrowest token scopes the service supports.
- Prefer optional secrets when commands can work anonymously.
- Never put a real value in `extension.json`, source, query text, saved data, or generated cURL output.
- Never include a secret in thrown errors, logs, reports, or action values.
- Do not use secret values as URLs because they can appear in server and proxy logs.
- Replacing a secret updates the Keychain item without exposing the old value to the settings UI.


## Design multiple commands

Prefer one package for commands that share:

- A domain or service.
- Parsing utilities.
- Persistent data.
- Permissions.
- A consistent mental model.

Dispatch by `commandID`:

```js
const handlers = {
  inspect: inspectCommand,
  list: listCommand,
  delete: deleteCommand,
};

runStoreExtension(async (invocation) => {
  const handler = handlers[invocation.commandID];
  if (!handler) throw new Error(`Unknown command: ${invocation.commandID}`);
  return handler(invocation);
});
```

Split unrelated capabilities into separate packages. Permissions are package-wide in API version 1, so a focused package avoids requesting capabilities that some commands never need.

## Argument syntax

Palette commands receive one query string. Define a predictable mini-syntax for structured input.

The examples use `|` separators:

```text
owner/repository | Issue title | Issue body
POST https://example.com/hook | {"hello":"world"} | Authorization: Bearer token
```

Parser:

```js
function parts(value) {
  return value.split("|").map((part) => part.trim());
}
```

For richer input:

- Accept JSON as the query.
- Support `name=value` pairs.
- Read a saved configuration from persistent storage.
- Open a web URL for complex creation forms.

Document escaping limitations. If `|` is valid inside payloads, use JSON input instead of a delimiter.

## Validation and errors

Throw concise, actionable errors:

```js
if (!repository.includes("/")) {
  throw new Error("Use owner/repository, for example apple/swift.");
}
```

Good errors include:

- What is wrong.
- The accepted format.
- A safe example.

Avoid:

- Stack traces as user messages.
- Leaking request authorization headers.
- Returning entire HTML error pages.
- Catching every error and pretending the command succeeded.

The SDK serializes thrown errors. Write developer diagnostics to standard error:

```js
console.error("Detailed diagnostic for extension developers");
```

Never write logs to standard output. Standard output is reserved for the JSON-RPC response.

## Raw protocol

The SDK is optional. Any executable JavaScript entrypoint that implements this protocol can work.

Vehla launches:

```text
node /absolute/package/path/index.js
```

It sends one newline-terminated request:

```json
{
  "jsonrpc": "2.0",
  "id": "request-uuid",
  "method": "store.invoke",
  "params": {
    "packageID": "com.example.my-extension",
    "commandID": "hello",
    "query": "world",
    "context": {
      "selectedText": "optional",
      "clipboardText": "optional",
      "frontmostApplication": "optional",
      "dataDirectory": "optional",
      "secrets": {
        "apiToken": "test-only-placeholder"
      }
    }
  }
}
```

Success response:

```json
{
  "jsonrpc": "2.0",
  "id": "request-uuid",
  "result": {
    "action": {
      "type": "copyText",
      "value": "Hello, world!"
    }
  }
}
```

Error response:

```json
{
  "jsonrpc": "2.0",
  "id": "request-uuid",
  "error": {
    "code": -32000,
    "message": "A useful error message."
  }
}
```

Requirements:

- `jsonrpc` must be `2.0`.
- Response `id` must match the request.
- Emit one response line.
- Keep standard output under 1 MB.
- Finish within 15 seconds.

## Execution environment

Each invocation receives a new child process.

The environment is intentionally reduced. It includes:

- `PATH`
- `HOME`
- `TMPDIR`
- `NO_COLOR=1`
- `TERM=dumb`
- `VEHLA_STORE_API_VERSION=1`

Common Node locations are included:

- `/opt/homebrew/bin`
- `/usr/local/bin`
- `/usr/bin`
- `/bin`

Do not depend on arbitrary parent-process environment variables.

The package directory is the process working directory, but resolve files from `import.meta.url` when practical.

## Security model

Install only trusted packages.

Current protections:

- Manifest validation.
- Relative entrypoint enforcement.
- Path containment checks.
- Rejection of symbolic links escaping the package.
- Reduced environment.
- Separate process crash isolation.
- Timeout and output limits.
- Declared broker capabilities.
- Ask, Allow, and Deny decisions.
- Keychain-backed storage for declared secrets.
- Required-secret launch checks and runtime diagnostic redaction.
- HTTP/HTTPS restriction for brokered URL opening.

Current limitation:

JavaScript is not executed in a security sandbox. The process runs under the user’s macOS account and may access resources independently of Vehla’s broker. Capability declarations do not contain arbitrary Node.js filesystem or network APIs.

Therefore:

- Review source before installation.
- Do not install unknown packages.
- Do not embed secrets in manifests.
- Do not commit credentials.
- Do not mistake Keychain storage for extension sandboxing.
- Do not assume `networkAccess` is a network firewall.
- Do not spawn arbitrary shell commands in community packages.

## Local testing

Test a command without opening Vehla:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"test","method":"store.invoke","params":{"packageID":"com.example.my-extension","commandID":"hello","query":"world","context":{}}}' \
  | node extensions/my-extension/index.js
```

Expected response:

```json
{"jsonrpc":"2.0","id":"test","result":{"action":{"type":"copyText","value":"Hello, world!"}}}
```

Test all meaningful branches:

- Valid explicit query.
- Selected-text fallback.
- Clipboard fallback.
- Empty input.
- Invalid input.
- Network timeout.
- Non-2xx response.
- Missing storage permission.
- Empty persistent state.
- Corrupt persistent state.
- Oversized remote response.

## Installation and updates

During local development:

1. Run `npm install --install-links`.
2. Install the package directory in Settings → Store.
3. Test its keywords.
4. Edit the source package.
5. Reinstall it to copy the new version into Vehla.

Vehla executes the installed copy, not the original development directory.

Keep package IDs stable between versions so enablement and permission state remain associated with the package.

## Troubleshooting

### Package does not install

Check:

- `extension.json` exists at the selected directory root.
- `apiVersion` is `1`.
- Package and command IDs contain only supported characters.
- The entrypoint exists.
- The entrypoint is relative.
- No symbolic link resolves outside the package.
- Commands are non-empty and IDs are unique.

### Command does not appear

Check:

- The package is enabled.
- The package has no entrypoint diagnostic.
- The command has a title.
- Search by title or an exact keyword.

### `node` cannot be launched

Install Node.js 20 or newer. Apple Silicon Homebrew commonly installs it at `/opt/homebrew/bin/node`; Intel Homebrew commonly uses `/usr/local/bin/node`.

### Module cannot be found

Run:

```sh
npm install --install-links
```

Confirm `node_modules/@vehla/store-sdk/index.js` exists inside the package before installation.

### Permission required

Open Settings → Store and change the requested capability to Ask or Allow. A Deny decision suppresses approval prompts.

### Command returns no useful input

Use an exact keyword with arguments, or grant selected-text/clipboard permission. Selecting by title intentionally provides an empty query.

### Network request times out

Use an `AbortSignal` timeout below 15 seconds and provide a compact error. Vehla terminates commands that exceed its invocation limit.

### Vehla reports an invalid response

Ensure:

- Standard output contains only one JSON response line.
- Logs go to standard error.
- The response ID matches the request.
- The process exits successfully.

## Included examples

### Hello Store

Minimal SDK and manifest introduction.

### Text Toolkit

Text input precedence, JSON validation, URL encoding, UUID generation, and timestamp conversion.

### GitHub Workflow

Browser actions, structured arguments, public API requests, rate-limit errors, and Markdown report generation.

### Web Inspector

HTTP methods, redirects, metadata parsing, headers, DNS promises, TLS sockets, timeouts, and bounded downloads.

### Webhook Runner

HTTP requests, request syntax, persistent records, atomic writes, response truncation, saved actions, and shell-safe cURL generation.

### Developer Security Tools

Cryptographic hashing, Base64, JWT inspection, secure randomness, numeric options, and HMAC generation.

## Publishing checklist

Before sharing a package:

- Use a stable reverse-domain package ID.
- Use a unique ID for every command.
- Request only necessary capabilities.
- Include a clear description and command subtitles.
- Document keyword syntax.
- Include a lockfile.
- Include all runtime dependencies.
- Remove development secrets.
- Test from a fresh clone.
- Test the installed copy.
- Test denied permissions.
- Test malformed input.
- Add timeouts and response limits.
- State whether remote data leaves the Mac.
- State where persistent data is stored.
- Include a license.

## Publish to the catalog

Catalog entries contain:

- The complete validated extension manifest.
- An HTTPS URL for a self-contained ZIP archive.
- The archive’s SHA-256 checksum.
- The relative package root inside the archive.

Build all archives and regenerate `catalog.json`:

```sh
python3 scripts/build-catalog.py
```

The build script:

1. Finds every directory under `extensions/` containing `extension.json`.
2. Runs `npm install --install-links` so local SDK dependencies are physically included.
3. Reuses an immutable matching archive or creates `packages/<directory>-<version>.zip`.
4. Calculates each archive’s SHA-256 checksum.
5. Rebuilds `catalog.json` from the extension manifests.

Package-specific `README.md` files are source documentation and are excluded from runtime archives. If an existing versioned archive differs from the remaining package contents, the build fails and requires a manifest version increment.

Before publishing:

```sh
git diff --check
git status
```

Test an archive independently:

```sh
temporary_directory="$(mktemp -d)"
ditto -x -k packages/my-extension-1.0.0.zip "$temporary_directory"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"test","method":"store.invoke","params":{"packageID":"com.example.my-extension","commandID":"hello","query":"world","context":{}}}' \
  | node "$temporary_directory/my-extension/index.js"
rm -rf "$temporary_directory"
```

Publishing rules:

- Increment the manifest version whenever archive contents change.
- Never replace a published version with different bytes.
- Commit the extension source, archive, and catalog update together.
- Keep archive URLs immutable and HTTPS-only.
- Do not add a catalog entry for an extension that has not been source-reviewed.
- Verify installation and invocation from Vehla after publication.

## Contributing

Contributions should add a focused package under `extensions/`.

Each package should include:

- `extension.json`
- `package.json`
- `package-lock.json`
- Entrypoint source
- A concise package-specific README when syntax is non-trivial

Keep examples readable. Prefer standard Node.js APIs over large dependencies. Explain security tradeoffs in comments or documentation.

## License

This repository is available under the MIT License.
