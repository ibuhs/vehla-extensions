# Z-Library

A compact native Vehla workspace inspired by the Raycast Z-Library extension.
It uses the `zlib` CLI to search and download books while keeping its queue and
settings in Vehla's private extension storage.

## Features

- Search by title, author, ISBN, or keyword.
- View authors, year, format, size, and rating.
- Download one book or select several for sequential bulk download.
- Save books to a persistent queue and download all pending entries.
- Open a result in the browser or copy its book ID.
- Configure a custom CLI path, download directory, and domain override.

## Setup

### 1. Install the CLI

```sh
brew install heartleo/tap/zlib
```

Confirm that Homebrew installed it:

```sh
zlib version
```

### 2. Find a healthy domain

The CLI requires a working Z-Library domain. Check the current candidates:

```sh
zlib doctor --eapi
```

Choose one whose status is `healthy`. Domains can change over time, so use the
doctor result rather than assuming the example below is still available.

### 3. Log in

Pass the healthy domain explicitly and use the EAPI:

```sh
zlib login --domain https://article.sk --eapi
```

Replace `https://article.sk` with the healthy domain you selected. Enter your
email and password interactively; avoid command-line password flags so the
password is not saved in shell history.

Verify the saved session:

```sh
ZLIB_DOMAIN=https://article.sk zlib profile
ZLIB_DOMAIN=https://article.sk zlib search "test" --json --count 2
```

### 4. Configure the Vehla workspace

Open **Z-Library → Settings**:

- **zlib Binary Path:** leave blank for automatic detection. Vehla checks
  `/opt/homebrew/bin/zlib`, `/usr/local/bin/zlib`, `~/.local/bin/zlib`, and
  the app's `PATH`. If detection fails, enter `/opt/homebrew/bin/zlib` on
  Apple silicon or `/usr/local/bin/zlib` on an Intel Mac.
- **Download Directory:** defaults to `~/Downloads`; enter a path or choose a
  folder.
- **Domain Override:** enter the exact healthy domain used to log in, including
  `https://`—for example, `https://article.sk`.

Click **Save**. A green status dot means the CLI launched successfully.

### Troubleshooting

- **“Set up the zlib CLI” remains visible:** enter the full binary path above,
  save, then close and reopen the workspace.
- **Domain is not configured:** set **Domain Override** to the same domain used
  for `zlib login`.
- **Search fails after previously working:** run `zlib doctor --eapi`, choose a
  new healthy domain, log in with that domain, and update **Domain Override**.
- **Session or authentication errors:** rerun `zlib login --domain <domain>
  --eapi`, then verify with `ZLIB_DOMAIN=<domain> zlib profile`.
- **After reinstalling an updated extension:** fully quit and reopen Vehla,
  because an already-loaded native workspace cannot be replaced in memory.

## Build and install

```sh
swift test
./build.sh
```

Install the generated `dist/ZLibrary` folder through Vehla's **Install Local
Package** workflow.

Downloads and access to Z-Library are handled by the third-party CLI. Follow
the laws and terms that apply to the material you access.
