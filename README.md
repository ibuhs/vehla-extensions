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
- Secret storage through Vehla’s Keychain.
- A security sandbox for JavaScript.
- In-process Swift extension bundles.

“Complex extension” currently means complex command logic, integrations, data processing, and persistent workflows. Custom visual interfaces and continuous services require future Store API versions.

## Repository layout

```text
vehla-extensions/
├── README.md
├── LICENSE
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

## Try an included extension

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

Do not store passwords, API keys, OAuth tokens, or production webhook secrets in plain JSON. API version 1 does not yet expose Keychain-backed secret storage.

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
      "dataDirectory": "optional"
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
- HTTP/HTTPS restriction for brokered URL opening.

Current limitation:

JavaScript is not executed in a security sandbox. The process runs under the user’s macOS account and may access resources independently of Vehla’s broker. Capability declarations do not contain arbitrary Node.js filesystem or network APIs.

Therefore:

- Review source before installation.
- Do not install unknown packages.
- Do not embed secrets in manifests.
- Do not commit credentials.
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
