# GLKB Cite

Select a scientific sentence on your Mac to find supporting literature on PubMed. Review the evidence excerpts, open a paper, and copy a formatted citation into your document.

**[Download GLKB Cite for Mac (.dmg)](https://github.com/RingoMao/GLKB-cite/releases/latest/download/GLKB-Cite.dmg)**

Version 0.2.0 (build 12) · Apple silicon (M-series) · macOS 13 Ventura or later

## Install and find your first citation

1. Open the downloaded disk image and drag **GLKB Cite** to **Applications**.
2. Open **GLKB Cite** from Applications. Its icon appears in the menu bar.
3. Follow setup to enable **GLKB Cite** under **System Settings → Privacy & Security → Accessibility** and save your GLKB API key. Contact the GLKB team if you need a key.
4. Select a scientific sentence in another app and press **Option–Command–G** or click the GLKB badge. Choose a PMID to read the paper or **Cite** to copy a reference.

The app sends your selection to GLKB when you request citations. Your API key is stored in macOS Keychain.

[Installation and troubleshooting](INSTALL.md) · [Release notes](https://github.com/RingoMao/GLKB-cite/releases/latest) · [Privacy](PRIVACY.md)

## What it does

- Runs in the menu bar without a Dock icon.
- Detects selected text through macOS Accessibility APIs.
- Shows a small GLKB badge near a valid selection; badge appearance never
  contacts the backend.
- Sends a request only after the user clicks the badge, presses `⌥⌘G`, invokes
  the menu command, or uses the macOS Service.
- Falls back, only when you have turned on **Allow temporary Copy fallback** (asked in the setup wizard, changeable in Settings → Privacy), to a guarded temporary Copy transaction
  for apps that do not expose selections through Accessibility.
- Calls the GLKB citation endpoint and presents deduplicated PubMed references,
  relevance reasons, and evidence excerpts.
- Copies a rich or plain-text report and opens results in PubMed.
- Formats any reference as MLA 9, APA 7, Chicago, Harvard or Vancouver (NLM),
  BibTeX or RIS. When the Cite modal opens, the volume, issue, pages, DOI,
  journal abbreviation and structured author names are fetched by PMID from
  PubMed's official E-utilities API; the citations fall back to GLKB's fields
  if PubMed cannot be reached.
- Coalesces identical in-flight requests and caches completed results in memory.
- Stores the user-provided `glkb_` credential only in macOS Keychain.

GLKB Cite is citation-only. It does not include HIRN QA or a general chatbot.

## Current GLKB API contract

```http
POST https://backend.glkb.org/reorg-api/api/v1/api-key-agent/cite
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

## Development requirements

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
