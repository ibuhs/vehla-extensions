# GitHub Workflow

GitHub navigation and public repository utilities for Vehla.

The extension opens repository workflows in your browser and fetches public repository metadata without requiring a GitHub token.

It demonstrates:

- Structured palette arguments.
- Safe URL construction with `URL` and `URLSearchParams`.
- Repository URL normalization and validation.
- Browser actions.
- Asynchronous public API requests.
- HTTP and rate-limit error handling.
- Markdown report generation.

## Install

Install **GitHub Workflow** from Settings → Store.

For local development:

```sh
npm --prefix extensions/github-workflow install --install-links
```

Then install `extensions/github-workflow` as a local package.

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

This command uses GitHub’s unauthenticated REST API.

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

The package does not store data or credentials.

## API behavior and rate limits

Only **Copy Repository Summary** calls the GitHub API. Other commands construct URLs locally and ask Vehla to open them.

Unauthenticated GitHub API requests have a low per-IP rate limit. When GitHub returns a failed response, the extension reports the HTTP status. If `X-RateLimit-Remaining` is zero, the error explains that the public limit was reached.

This example intentionally does not accept personal access tokens because Store API version 1 does not provide Keychain-backed secret storage.

## Security notes

- Issue creation opens a prefilled page; it never submits content automatically.
- Repository and username input is validated before URL construction.
- Query values are encoded with `URLSearchParams`.
- No shell commands are executed.
- Do not modify this example to place access tokens directly in source or manifests.

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
- Add authenticated operations after a secrets API exists.
- Save frequently used repositories with persistent storage.
- Add organization and contributor summaries.

For the Store protocol and publishing requirements, see the repository-level README.
