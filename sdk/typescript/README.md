# Vehla Store SDK

Store packages are directories containing an `extension.json` manifest and a JavaScript entrypoint. Vehla launches the entrypoint in a separate Node.js process and sends one newline-delimited JSON-RPC invocation through standard input.

## Try the example

Requirements: Node.js 20 or newer.

```sh
cd extensions/hello-store
npm install --install-links
```

Open Vehla Settings → Store → Install Local Package, select `extensions/hello-store`, and enable the permissions required by the commands. Search the palette for `hello`, `greet`, or `storecopy`.

`--install-links` copies the local SDK into `node_modules` so the installed package remains self-contained.

## Package shape

```text
my-package/
  extension.json
  index.js
  node_modules/
  package.json
```

The manifest declares an API version, package identity, entrypoint, commands, capabilities, and optional secrets. Command IDs are namespaced by Vehla using the package ID.

The entrypoint should call `runStoreExtension` once:

```js
import { Store, runStoreExtension } from "@vehla/store-sdk";

runStoreExtension(async ({ commandID, query, context }) => {
  if (commandID === "copy") {
    return Store.copyText(query || context.selectedText || "");
  }
  return Store.showMessage("Done");
});
```

Write diagnostics to standard error. Standard output is reserved for the protocol response and is limited to 1 MB. A command has 15 seconds to finish.

## Capabilities

Capabilities must be declared in `extension.json` and allowed by the user in Store settings. API version 1 recognizes:

- `clipboardRead`
- `clipboardWrite`
- `openURL`
- `notifications`
- `selectedText`
- `userSelectedFiles`
- `networkAccess`
- `persistentStorage`

The current command API implements clipboard input/output, selected-text input, HTTP/HTTPS URL opening, message display, explicit network launch consent, and a private persistent data directory. Additional broker APIs can be added without changing the package process boundary.

## Secrets

Declare credentials by ID, label, description, and whether they are required in `extension.json`. Users configure values in Store settings; Vehla stores them in the macOS Keychain and passes configured values through `context.secrets`.

```js
const token = context.secrets.apiToken;
```

Required secrets prevent invocation until configured. Never log, persist, return, or embed secret values in source or manifests.

## Forms and rich results

Commands may declare a native form in `extension.json`. Submitted text, secure text, multiline text, toggle, and select values are available through `context.formValues`. Secure text is transient and is redacted from runtime diagnostics.

Return `Store.view(...)` for a native structured result containing text, Markdown, code, detail rows, and brokered action buttons:

```js
return Store.view({
  title: "Completed",
  sections: [{
    title: "Response",
    items: [{ type: "code", language: "json", text: "{}" }],
  }],
});
```

`file` and `files` form fields open Vehla’s native picker and return `StoreSelectedFile` metadata. Packages using them must declare `userSelectedFiles`.

Return `Store.notify(title, body)` to request a brokered macOS notification after declaring the `notifications` capability.

Vehla validates and renders the schema. Packages cannot inject arbitrary UI code.
