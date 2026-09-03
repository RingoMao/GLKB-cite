# Contributing to GLKB Cite

Thank you for helping build GLKB Cite. The project accepts focused issues and
pull requests under the Apache License 2.0.

## Development workflow

1. Create a feature branch from `main`.
2. Make the smallest coherent change and include deterministic tests.
3. Run `swift test` and `./Scripts/run-offline-checks.sh` on macOS.
4. Confirm the change does not add credentials, selected user text, API
   responses from real users, certificates, or signed binaries.
5. Open a pull request describing behavior, privacy impact, test evidence, and
   whether the API contract changes.

Routine tests must use `URLProtocol` mocks, named pasteboards, and recorded
synthetic fixtures. Do not call the production GLKB API in CI. A live smoke test
requires explicit team approval because requests may consume paid resources and
transmit selected text.

Changes to clipboard capture, Accessibility events, Keychain handling, update
signing, or request logging require an explicit security and privacy review.

## API compatibility

The current endpoint accepts only `text` and `max_references`. Preserve typed
handling for authentication, validation, upstream, and timeout failures. Treat
new response fields as untrusted input and keep PMID normalization and
deduplication covered by tests.

## Licensing and provenance

Unless explicitly stated otherwise, contributions are submitted under section
5 of the Apache License 2.0 included in this repository. Contributors must have
the right to submit their changes. Do not copy code, icons, layouts, or other
assets from PopClip or from repositories whose license does not permit reuse.

The app talks to GLKB, but that does not make this repository a derivative of
the `GLKB_tools` source repository. Attribute and cite the GLKB scientific work
through README.md and CITATION.cff. If future code is imported from another
project, record its exact source, revision, license, and required notices before
merging it.
