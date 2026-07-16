# Hello Store

A minimal Vehla extension showing the smallest useful Store package.

Use this example to learn:

- How `extension.json` declares package metadata and commands.
- How palette keywords become `query`.
- How selected text can be used as fallback input.
- How to return message and clipboard actions.
- How the SDK handles JSON-RPC input and output.

## Install

From Vehla, open Settings → Store, refresh the catalog, and install **Hello Store**.

For local development:

```sh
npm --prefix extensions/hello-store install --install-links
```

Then choose `extensions/hello-store` through **Install Local Package**.

## Commands

### Greet from Store

Keywords: `hello`, `greet`

```text
hello Shubham
greet Store developer
```

Input precedence:

1. Text following the keyword.
2. Selected text.
3. The default subject `there`.

Result: Vehla displays an informational message such as:

```text
Hello, Shubham!
```

### Copy from Store

Keyword: `storecopy`

```text
storecopy Hello from my extension
```

Input precedence:

1. Text following the keyword.
2. Selected text.
3. The default text `Hello from Vehla Store`.

Result: the selected value is copied to the clipboard.

## Permissions

The package declares:

- `clipboardWrite` — required by **Copy from Store**.
- `selectedText` — allows both commands to use selected text when no explicit query is supplied.

The greeting command does not require clipboard access. Permissions are package-wide in Store API version 1, so Vehla shows every declared capability for the package.

## Package structure

```text
hello-store/
├── extension.json
├── index.js
├── package.json
├── package-lock.json
└── README.md
```

`extension.json` defines two commands. `index.js` calls `runStoreExtension` once and dispatches using `commandID`.

The complete handler is intentionally small:

```js
runStoreExtension(async ({ commandID, query, context }) => {
  if (commandID === "copy") {
    return Store.copyText(query || context.selectedText || "Hello from Vehla Store");
  }

  if (commandID === "greet") {
    return Store.showMessage(`Hello, ${query || context.selectedText || "there"}!`);
  }

  throw new Error(`Unknown command: ${commandID}`);
});
```

Important patterns:

- Explicit query input wins over ambient context.
- Every declared command has a matching handler branch.
- Unknown command IDs produce a useful error.
- The handler returns a structured Store action instead of directly controlling macOS.

## Test outside Vehla

Install dependencies, then send a JSON-RPC request through standard input:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"hello-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.hello","commandID":"greet","query":"Developer","context":{}}}' \
  | node extensions/hello-store/index.js
```

Expected response:

```json
{
  "jsonrpc": "2.0",
  "id": "hello-test",
  "result": {
    "action": {
      "type": "showMessage",
      "value": "Hello, Developer!"
    }
  }
}
```

Test selected-text fallback:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"selection-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.hello","commandID":"copy","query":"","context":{"selectedText":"Selected value"}}}' \
  | node extensions/hello-store/index.js
```

## Extend this example

Good next exercises:

1. Add a command to uppercase input.
2. Declare `clipboardRead` and add clipboard fallback.
3. Return a `message` together with a `copyText` action.
4. Add input validation and intentionally test the error response.
5. Split command handlers into a lookup object instead of `if` statements.

For the complete platform contract, see the repository-level README.
