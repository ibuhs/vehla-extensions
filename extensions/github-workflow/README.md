# GitHub Workflow

GitHub navigation and repository utilities for Vehla.

The extension opens repository workflows in your browser and fetches public repository metadata anonymously. An optional Keychain-backed token enables private repository summaries and higher API rate limits.

It demonstrates:

- Structured palette arguments.
- Safe URL construction with `URL` and `URLSearchParams`.
- Repository URL normalization and validation.
- Browser actions.
- Asynchronous public API requests.
- Secure optional authentication with a manifest-declared secret.
- HTTP and rate-limit error handling.
- Markdown report generation.

## Install

Install **GitHub Workflow** from Settings → Store.

For local development:

```sh
npm --prefix extensions/github-workflow install --install-links
```

Then install `extensions/github-workflow` as a local package.

To configure authentication, open the installed package in Store settings and save a fine-grained token under **GitHub Personal Access Token**. The extension works without it for public repositories.

## Input behavior

Commands use explicit query text first, followed by selected text and clipboard text.

Repository arguments accept either:

```text
apple/swift
```

or:

```text
https://github.com/apple/swift
```

The parser removes `.git` and common `/issues`, `/pull`, and `/compare` suffixes before validating `owner/repository`.

Commands with multiple fields use `|` separators.

## Commands

### Search GitHub

Keyword: `ghsearch`

Search repositories by default:

```text
ghsearch swift speech recognition
```

Specify a search type:

```text
ghsearch repositories | swift package manager
ghsearch code | StoreManifest language:swift
ghsearch issues | is:open crash SIGPIPE
ghsearch users | octocat
```

Supported aliases:

- `repositories`
- `repos`
- `code`
- `issues`
- `users`

Result: opens GitHub’s search page in the default browser.

### Open GitHub Repository

Keyword: `ghrepo`

```text
ghrepo apple/swift
ghrepo https://github.com/apple/swift.git
```

Result: opens the repository.

### Copy Repository Summary

Keyword: `ghsummary`

```text
ghsummary apple/swift
```

Result: fetches `https://api.github.com/repos/apple/swift` and copies a Markdown report containing:

- Description
- Stars
- Forks
- Open issues
- Primary language
- Default branch
- License
- Visibility
- Last push time
- Repository URL

This command uses GitHub’s REST API. It sends `Authorization: Bearer <token>` only when the optional `githubToken` secret is configured.

### Draft GitHub Issue

Keyword: `ghissue`

```text
ghissue owner/repository | Incorrect response status | Steps to reproduce the issue
```

Result: opens the repository’s new-issue page with the title and body prefilled. It does not submit the issue.

Everything after the second separator is joined back into the body, allowing additional `|` characters.

### Open GitHub Pull Request

Keyword: `ghpr`

```text
ghpr owner/repository | 42
```

Result: opens pull request 42.

The pull request number must contain digits only.

### Compare GitHub Branches

Keyword: `ghcompare`

```text
ghcompare owner/repository | main | feature/store-catalog
```

Result: opens:

```text
https://github.com/owner/repository/compare/main...feature/store-catalog
```

### Open GitHub Profile

Keyword: `ghuser`

```text
ghuser octocat
ghuser @octocat
```

The optional leading `@` is removed. Usernames may contain letters, numbers, and hyphens.

## Permissions

- `clipboardRead` — allows repository or command input from the clipboard.
- `clipboardWrite` — copies repository summaries.
- `selectedText` — allows selected repository text as input.
- `openURL` — opens GitHub pages.
- `networkAccess` — permits the package to launch when using GitHub’s API.

The package declares one optional secret:

- `githubToken` — a GitHub personal access token stored by Vehla in the macOS Keychain.

The settings UI never reveals an existing value. The extension receives it only in the invocation context.

## API behavior and rate limits

Only **Copy Repository Summary** calls the GitHub API. Other commands construct URLs locally and ask Vehla to open them.

Unauthenticated GitHub API requests have a low per-IP rate limit. Authenticated requests receive a higher limit and can read repositories the token can access. When GitHub returns a failed response, the extension reports the HTTP status. If `X-RateLimit-Remaining` is zero, the error explains that the limit was reached.

Use a fine-grained, read-only token restricted to the repositories required by this command. Browser commands do not use the token.

## Security notes

- Issue creation opens a prefilled page; it never submits content automatically.
- Repository and username input is validated before URL construction.
- Query values are encoded with `URLSearchParams`.
- No shell commands are executed.
- Token values are never placed in source, manifests, persistent files, action output, or error text.
- Keychain storage protects the token at rest, but the trusted extension process receives it while the command runs.

## Test outside Vehla

Test URL generation without opening a browser:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"repo-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.github-workflow","commandID":"open-repository","query":"apple/swift","context":{}}}' \
  | node extensions/github-workflow/index.js
```

Test the public API:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"summary-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.github-workflow","commandID":"repository-summary","query":"apple/swift","context":{}}}' \
  | node extensions/github-workflow/index.js
```

## Extension ideas

- Add release and tag navigation.
- Build commit or blame URLs from selected file paths.
- Add authenticated issue and pull-request API operations with narrowly scoped tokens.
- Save frequently used repositories with persistent storage.
- Add organization and contributor summaries.

For the Store protocol and publishing requirements, see the repository-level README.
