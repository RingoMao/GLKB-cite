# GLKB Cite

GLKB Cite is a native macOS menu-bar app for finding biomedical citations from
selected text. Its core workflow is simple:

> Select text -> Click GLKB cite button -> Request GLKB -> Return references

The app is a team-development handoff of the working macOS demo. It is a
clean-room implementation built with public Apple APIs and does not contain or
depend on PopClip.

> **Project status:** internal alpha. Source builds are usable for development,
> but builds for other users must be Developer ID signed and notarized first.

## What it does

- Runs in the menu bar without a Dock icon.
- Detects selected text through macOS Accessibility APIs.
- Shows a small GLKB badge near a valid selection; badge appearance never
  contacts the backend.
- Sends a request only after the user clicks the badge, presses `⌥⌘G`, invokes
  the menu command, or uses the macOS Service.
- Falls back, when explicitly enabled, to a guarded temporary Copy transaction
  for apps that do not expose selections through Accessibility.
- Calls the GLKB citation endpoint and presents deduplicated PubMed references,
  relevance reasons, and evidence excerpts.
- Copies a rich or plain-text report and opens results in PubMed.
- Coalesces identical in-flight requests and caches completed results in memory.
- Stores the user-provided `glkb_` credential only in macOS Keychain.

GLKB Cite is citation-only. It does not include HIRN QA or a general chatbot.

## Current GLKB API contract

```http
POST https://jieliulab3.dcmb.med.umich.edu/reorg-api/api/v1/api-key-agent/cite
Authorization: Bearer glkb_…
Content-Type: application/json

{
  "text": "One scientific sentence, 10–1000 characters.",
  "max_references": 5
}
```

The parser accepts terminal `status` values `ok` and `no_results`. Reference
fields include PMID, title, URL, citation count, date, journal, authors,
evidence, and `why`. The client uses a 90-second request timeout and surfaces
authentication, validation, upstream, and timeout errors without logging the
credential or selected text.

Do not put an API key in this repository, fixtures, shell history, logs, or the
application bundle.

## Requirements

- macOS 13 or later
- Swift 6 / Xcode 16 or later for development
- Accessibility permission for cross-application selection capture
- A valid GLKB API key for live requests
- Full Xcode and an Apple Developer team for distributable builds

## Build and test

Clone the repository, then run the deterministic offline test suite:

```sh
git clone https://github.com/RingoMao/GLKB-cite.git
cd GLKB-cite
swift test
./Scripts/run-offline-checks.sh
```

Tests and CI use mocked networking and recorded fixtures. They do not contact
the live GLKB endpoint.

Build an ad-hoc signed development app and DMG:

```sh
BUILD_MODE=development ./Scripts/build-app.sh
```

Artifacts are written to `.build/app/`. See [INSTALL.md](INSTALL.md) for local
installation and [DISTRIBUTION.md](DISTRIBUTION.md) for Developer ID signing,
notarization, and release gates.

## Architecture

```text
Sources/GLKBCiteCore/     API contract, validation, response parsing, cache,
                         normalization, PubMed links, report formatting
Sources/GLKBCiteMac/      menu-bar lifecycle, Accessibility/clipboard/Service
                         capture, shortcuts, Keychain, panels, settings
Tests/                    mocked API and deterministic capture/cache tests
Scripts/                  offline checks and app/release packaging
Resources/                app icon and signing entitlements
```

The core boundary is `LiteratureBackend`. `GLKBBackend` implements it with an
ephemeral `URLSession`; `CachingLiteratureBackend` adds same-query in-flight
coalescing and memory-only caching. UI code consumes progress and final result
events without knowing the wire format.

## Team development

Before opening a pull request:

1. Keep user-selected text, responses, and credentials out of logs and fixtures.
2. Add or update offline tests for behavioral changes.
3. Run `swift test` and `./Scripts/run-offline-checks.sh`.
4. Do not perform live API tests unless the team explicitly approves the call.
5. Keep the bundle identifier `org.glkb.cite` and Keychain service stable.

See [CONTRIBUTING.md](CONTRIBUTING.md), [API integration](docs/API.md),
[PRIVACY.md](PRIVACY.md), and [SECURITY.md](SECURITY.md).

## Attribution and citation

GLKB Cite uses the GLKB citation service. For scientific work enabled by GLKB,
cite the GLKB resource paper:

> Huang Y, Han Z, Luo X, et al. *Building a literature knowledge base towards
> transparent biomedical AI.* bioRxiv (2024).
> https://doi.org/10.1101/2024.09.22.614323

Machine-readable project citation metadata is in [CITATION.cff](CITATION.cff).
This repository did not copy source code from PopClip or from `GLKB_tools`.

## License

Code in this repository is licensed under the
[Apache License 2.0](LICENSE). Contributions are accepted under the same terms.
Apache-2.0 does not grant rights to project names, logos, service marks, API
access, datasets, or third-party content. See [NOTICE](NOTICE) and
[THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).
