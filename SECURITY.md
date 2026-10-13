# Security policy

## Reporting a vulnerability

Do not open a public issue containing an API key, selected user text, private
literature results, signing material, or details of an exploitable
vulnerability.

Report privately through GitHub's private vulnerability reporting on this
repository (*Security → Report a vulnerability*). A dedicated contact address
will be added here by the University of Michigan maintainers before the first
public release:

> Security contact: **TBD — to be set by the maintainers before public release**

Rotate any exposed credential immediately; a GLKB key can be replaced in
Settings → Literature.

## Secrets

- GLKB keys belong in the macOS Keychain service `org.glkb.cite` only.
- Never commit keys, `.env` files, certificates, notarization credentials, or
  Sparkle private keys.
- Never log request Authorization headers, selected text, or response bodies.
- A Developer ID private key is generated on, and never leaves, the signing
  Mac; it is never exported or sent as a `.p12`.
- Release credentials belong in protected CI secrets or a local Keychain.

## Supported versions

Until the first signed public release, only the latest commit on `main`
receives security fixes. Ad-hoc development builds and Developer ID tester
builds are not distribution artifacts.
