#!/bin/bash
#
# Guided, one-time setup for producing notarized GLKB Cite builds.
#
# Run this yourself: it never receives your Apple password. The only secret it
# touches is typed by you directly into Apple's `notarytool`, which stores it in
# your login Keychain under the profile name below.

set -euo pipefail

PROFILE="${NOTARY_PROFILE:-GLKBCite-Notary}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
todo() { printf '  ✗ %s\n' "$*"; }

bold "1. Xcode command-line tools"
if xcrun --find notarytool >/dev/null 2>&1 && xcrun --find stapler >/dev/null 2>&1; then
    ok "notarytool and stapler are available ($(xcodebuild -version 2>/dev/null | head -n 1))"
else
    todo "Full Xcode is required (notarytool/stapler). Install Xcode from the App Store, then re-run."
    exit 1
fi

bold "2. Developer ID Application certificate"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' || true)"
if [[ -n "$IDENTITIES" ]]; then
    printf '%s\n' "$IDENTITIES" | sed -E 's/^ *[0-9]+\) [0-9A-F]+ /  ✓ /'
    IDENTITY_NAME="$(printf '%s\n' "$IDENTITIES" | head -n 1 | sed -E 's/^.*"(.*)".*$/\1/')"
    TEAM_ID="$(printf '%s' "$IDENTITY_NAME" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
    if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        todo "Could not read a 10-character Team ID from the identity name: $IDENTITY_NAME"
        exit 1
    fi
    if [[ "$(printf '%s\n' "$IDENTITIES" | grep -c .)" -gt 1 ]]; then
        printf '  ! several identities: pass DEVELOPER_ID_APPLICATION="…" to release-tester.sh\n'
    fi
else
    todo "No 'Developer ID Application' certificate in your Keychain."
    cat <<'STEPS'
    How to get one (Apple only lets a team's Account Holder create Developer ID certificates):
      a. Be a member of the University of Michigan Apple Developer Program team
         (or enrol: https://developer.apple.com/programs/enroll/ — an educational fee waiver exists).
      b. In Xcode: Settings → Accounts → add your Apple ID → select the team →
         Manage Certificates… → “+” → Developer ID Application.
         If “+” does not offer it, create a certificate signing request on THIS Mac
         (Keychain Access → Certificate Assistant → Request a Certificate From a
         Certificate Authority…, saved to disk) and ask the Account Holder to issue a
         Developer ID Application certificate from it at
         https://developer.apple.com/account/resources/certificates/add.
         The private key is generated here and never leaves this Mac. A Developer ID
         private key must never be exported, emailed, or shared (no .p12 hand-offs):
         anyone holding it can sign software as the university.
      c. Double-click the issued .cer so it lands in your login Keychain, then re-run this script.
STEPS
    exit 1
fi

bold "3. Notarization credentials (Keychain profile: $PROFILE)"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    ok "profile '$PROFILE' exists and authenticates"
else
    todo "profile '$PROFILE' is missing or invalid."
    cat <<STEPS
    You need an app-specific password for your Apple ID:
      a. Sign in at https://account.apple.com → Sign-In and Security → App-Specific Passwords → "+".
      b. Name it "GLKB Cite notarization" and copy the generated password.
    notarytool will now prompt you for: Apple ID (email), Team ID (${TEAM_ID:-from step 2}), and that password.
    The values are stored in your Keychain — they are not echoed, logged, or seen by anyone else.

STEPS
    xcrun notarytool store-credentials "$PROFILE" --team-id "${TEAM_ID:-}" || {
        todo "Credential storage did not complete. Re-run this script to try again."
        exit 1
    }
    xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null
    ok "profile '$PROFILE' stored and verified"
fi

bold "Ready. Build a notarized tester DMG with:"
printf '  DEVELOPER_ID_APPLICATION="%s" ./Scripts/release-tester.sh\n' "$IDENTITY_NAME"
