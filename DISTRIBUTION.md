# Distribution and release handoff

GLKB Cite is intentionally distributed outside the Mac App Store so it can use
the macOS Accessibility API to read the current cross-application selection.

## Apple organization setup

1. Use the University of Michigan legal entity's Apple Developer Program team.
2. Confirm the account holder has organizational authority and team access.
3. Request Apple's accredited-educational-institution fee waiver.
4. Create a Developer ID Application certificate for release signing.
5. Create an app-specific notarization credential and store it in a CI secret
   or local Keychain profile. Never commit certificate material or passwords.

The program costs USD 99 per year if the fee waiver is not approved. Developer
ID signing and notarization have no separate per-app fee.

## Build and notarize

Full Xcode is required for the release SDK and signing tools.

```sh
BUILD_MODE=distribution \
DEVELOPER_ID_APPLICATION="Developer ID Application: University of Michigan (…)" \
SPARKLE_PUBLIC_KEY="base64-ed25519-public-key" \
SPARKLE_FEED_URL="https://official.example.org/glkb-cite/appcast.xml" \
VERSION="0.1.1" BUILD_NUMBER="2" UNIVERSAL=1 CONFIGURATION=release \
"./Scripts/build-app.sh"

NOTARY_PROFILE="GLKBCite-Notary" \
"./Scripts/notarize.sh" \
"./.build/app/GLKB Cite.dmg"
```

Distribution mode fails before packaging unless the build is universal and
release-configured, a non-ad-hoc signing identity is supplied, both Sparkle
values are valid, and a DMG is produced. It signs Sparkle's nested helpers
inside-out, signs the app and DMG, and runs `verify-release.sh preflight`.
The DMG contains the app, an `/Applications` shortcut for drag installation,
and the same `INSTALL.md` first-run guide tracked with the source.
Notarization requires a named Keychain profile, accepts only an `Accepted`
result, staples both sibling app and DMG, then runs the Gatekeeper postflight.

Never publish the development-mode artifact. Keep the same bundle identifier,
Developer ID team, and Sparkle key across upgrades unless following Sparkle's
documented key-rotation process.

## Sparkle updates

Sparkle is linked through Swift Package Manager. Before public release:

1. Generate and securely store a Sparkle EdDSA private key using Sparkle's
   `generate_keys` tool. The public key goes in the build environment; the
   private key remains in Keychain or a protected key file.
2. Build and notarize the DMG using the commands above. Do not sign the update
   archive until its bytes are final and its notarization ticket is stapled.
3. Run Sparkle 2.9.5's `sign_update "GLKB Cite.dmg"` and place the emitted
   EdDSA signature and length on the appcast enclosure.
4. If release notes are external, run `sign_update release-notes.html` first
   and place its emitted signature and length on `sparkle:releaseNotesLink`.
5. Run `sign_update appcast.xml` last. This modifies the XML to embed the feed
   signature required by `SURequireSignedFeed`. After any XML or release-note
   edit, repeat the applicable signing steps.
6. Run `sign_update --verify appcast.xml`, then publish the signed appcast,
   signed release notes, and notarized update over HTTPS from an official host.
7. Keep the private update key, Developer ID material, and notarization
   credentials outside the repository and CI logs.

Every packaged Info.plist enables `SURequireSignedFeed` and
`SUVerifyUpdateBeforeExtraction`. The updater itself remains disabled when a
public key and feed URL have not been injected into a development build.

## Privacy and license release review

Before a public build, obtain written confirmation from the GLKB operator about
whether selected text, authorization/account data,
IP addresses, responses, or request metadata are retained after servicing the
request. The current empty `NSPrivacyCollectedDataTypes` declaration is valid
only if readable content is not retained beyond servicing under Apple's data
collection definition. If the service retains it, update the manifest and
hosted privacy notice before shipping. Record the retention period, purposes,
linked-to-user status, deletion route, operator identity, and privacy contact.

`THIRD-PARTY-NOTICES.txt` contains the complete Sparkle 2.9.5 and bundled
component notices. It must remain in `Contents/Resources` and accessible from
the app menu.

## Release gates

- The publisher completes project-name and trademark clearance before any public release.
- `verify-release.sh preflight` succeeds before notarization.
- `verify-release.sh postflight` validates signatures, tickets and Gatekeeper.
- An extracted bundle contains no `glkb_` credential or selected-text fixture.
- The root privacy manifest, full notices, expected Sparkle 2.9.5 framework,
  secure feed keys, rpath and both architecture slices are present.
- Backend retention review and the hosted privacy contact are complete.
- Up to three explicitly approved GLKB smoke requests pass within the locked call budget;
  automated tests remain fixture-only.
