# Developer Security Tools

Local hashing, encoding, token inspection, and secure random generation commands for Vehla.

This educational extension demonstrates:

- Node.js cryptography APIs.
- UTF-8 hashing.
- Base64 and Base64URL handling.
- Structured token parsing.
- Cryptographically secure random bytes and integers.
- Bounded numeric options.
- HMAC generation.
- Explicit warnings when an operation does not provide verification.

## Install

Install **Developer Security Tools** from Settings → Store.

For local development:

```sh
npm --prefix extensions/developer-security-tools install --install-links
```

Then install `extensions/developer-security-tools` as a local package.

## Input behavior

Text-processing commands use:

1. Explicit palette query.
2. Selected text.
3. Clipboard text.

Password and token generators intentionally read options only from the explicit query. Clipboard or selected text is never interpreted as a requested length.

All results are copied to the clipboard.

## Commands

### SHA-256 Hash

Keyword: `sha256`

```text
sha256 hello
```

Output:

```text
2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
```

The input is encoded as UTF-8 and the digest is lowercase hexadecimal.

### SHA-512 Hash

Keyword: `sha512`

```text
sha512 hello
```

Output is a 128-character lowercase hexadecimal digest.

Hashing is one-way but is not encryption. Plain SHA hashes are not suitable for password storage; use a purpose-built password hashing algorithm such as Argon2, scrypt, or bcrypt.

### Base64 Encode

Keyword: `b64encode`

```text
b64encode Hello, Vehla!
```

Output:

```text
SGVsbG8sIFZlaGxhIQ==
```

Base64 is an encoding, not encryption.

### Base64 Decode

Keyword: `b64decode`

```text
b64decode SGVsbG8sIFZlaGxhIQ==
```

Both standard Base64 and Base64URL alphabets are accepted. Output is decoded as UTF-8; arbitrary binary content may not display correctly.

The input is checked for unsupported characters before decoding.

### Decode JWT

Keyword: `jwt`

```text
jwt eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMiLCJleHAiOjE4MDAwMDAwMDB9.signature
```

The copied JSON report includes:

- Decoded header.
- Decoded payload.
- Original signature segment.
- ISO dates for numeric `iat`, `nbf`, and `exp` claims.
- Whether `exp` is in the past.
- An explicit signature-verification warning.

This command **does not verify the JWT signature**. Decoded claims are untrusted data.

### Generate Secure Password

Keyword: `password`

Default length:

```text
password
```

Custom length:

```text
password 32
```

Allowed range: 12–128 characters. Default: 24.

Generated passwords contain at least one character from each group:

- Uppercase letters without easily confused `I` and `O`.
- Lowercase letters without easily confused `l`.
- Digits 2–9.
- Symbols.

Characters and the final shuffle use `crypto.randomInt`.

### Generate Random Token

Keyword: `token`

```text
token
token 48
```

The argument is the number of random bytes, not the output character count.

Allowed range: 8–128 bytes. Default: 32 bytes.

Output uses unpadded Base64URL, making it suitable for URL-safe identifiers and development secrets.

### Create HMAC-SHA256

Keyword: `hmac`

Syntax:

```text
hmac secret | message
```

Example:

```text
hmac development-secret | body to authenticate
```

Output is a lowercase hexadecimal HMAC-SHA256 digest.

Everything after the first `|` is joined back into the message, so the message may itself contain separators.

## Permissions

- `clipboardRead` — enables clipboard fallback for processing commands.
- `clipboardWrite` — copies every result.
- `selectedText` — enables selected-text fallback.

The extension performs no network requests and stores no persistent data.

## Security guidance

These tools are useful for development and inspection, but they do not replace a complete security product.

- Do not paste production secrets into untrusted extensions.
- JWT decoding does not establish authenticity.
- Base64 does not provide confidentiality.
- SHA-256 and SHA-512 are not password hashing functions.
- HMAC security depends on a secret with sufficient entropy.
- Clipboard output remains available to other applications with clipboard access.
- Avoid entering production HMAC secrets in this example package.

The source uses only Node.js built-ins, reducing dependency risk.

## Implementation details

### Bounded options

`boundedInteger` rejects:

- Fractional values.
- Non-numeric values.
- Values outside a command-specific range.

This prevents accidental generation of unexpectedly large output.

### Password construction

The generator first chooses one random character from each required group. It fills the remaining positions from the combined alphabet, then performs a Fisher–Yates shuffle using secure random indices.

### Base64URL decoding

The decoder:

1. Replaces `-` with `+`.
2. Replaces `_` with `/`.
3. Restores required `=` padding.
4. Decodes as Base64.
5. Converts the bytes to UTF-8.

## Test outside Vehla

Hash:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"hash-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.developer-security-tools","commandID":"sha256","query":"hello","context":{}}}' \
  | node extensions/developer-security-tools/index.js
```

Generate a password:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"password-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.developer-security-tools","commandID":"password","query":"32","context":{}}}' \
  | node extensions/developer-security-tools/index.js
```

Test selected-text fallback:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"base64-test","method":"store.invoke","params":{"packageID":"com.vehla.examples.developer-security-tools","commandID":"base64-encode","query":"","context":{"selectedText":"selected value"}}}' \
  | node extensions/developer-security-tools/index.js
```

## Extension ideas

- Add checksum verification against an expected digest.
- Add UUID variants.
- Add PEM certificate inspection.
- Add cryptographically safe passphrases from a bundled word list.
- Add JWK parsing and signature verification after secure key input exists.
- Add clipboard auto-clear support when exposed by the Store API.

For the full extension contract, see the repository-level README.
