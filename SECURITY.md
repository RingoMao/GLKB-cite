# Security policy

## Reporting

Do not open a public issue containing an API key, selected user text, private
literature results, signing material, or an exploitable vulnerability. Contact
the repository maintainers privately through GitHub and rotate any exposed
credential immediately.

## Secrets

- GLKB keys belong in macOS Keychain service `org.glkb.cite` only.
- Never commit keys, `.env` files, certificates, notarization credentials, or
  Sparkle private keys.
- Never log request Authorization headers, selected text, or response bodies.
- Release credentials belong in protected CI secrets or a local Keychain.

## Supported versions

Until the first signed beta, only the latest commit on `main` receives security
fixes. Ad-hoc development builds are not distribution artifacts.
