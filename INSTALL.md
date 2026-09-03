# Install GLKB Cite on macOS

## For testers receiving a DMG

1. Quit GLKB Lens and any older GLKB Cite build. GLKB Lens may use the same
   `⌥⌘G` shortcut.
2. Open `GLKB Cite.dmg`.
3. Drag **GLKB Cite** onto the **Applications** shortcut.
4. Eject **GLKB Cite Installer**.
5. Launch `/Applications/GLKB Cite.app`; do not run the copy inside the DMG.

A build shared with other people must be signed with the project's stable Apple
Developer ID and notarized. An ad-hoc development build can trigger macOS's
unknown-developer warning and may need Accessibility approval again after each
rebuild.

## First run

1. Select **Request Access** in onboarding.
2. In **System Settings → Privacy & Security → Accessibility**, enable the
   `/Applications/GLKB Cite.app` entry.
3. Return to GLKB Cite, paste an active `glkb_` API key, and select **Save**.
   The key is stored as a generic password in macOS Keychain under service
   `org.glkb.cite`.
4. Read the Compatibility Capture disclosure and finish setup.
5. Select one scientific sentence (10–1000 characters) in another app, then
   click the GLKB badge or press `⌥⌘G`.

The badge itself causes no API request. Compatibility Capture may temporarily
invoke Copy only when Accessibility cannot expose a selection and the gesture is
eligible. It restores the previous clipboard only when safe; clipboard-history
utilities can still observe the temporary selection. Disable this fallback in
**GLKB Cite Settings → Privacy** at any time.

For unsupported PDF controls, try the macOS Service named **Find Citations with
GLKB Cite** from the application's Services menu.

## Troubleshooting

### Accessibility is enabled but selection capture fails

1. Quit GLKB Cite.
2. Remove any stale GLKB Cite entry from Accessibility settings.
3. Add `/Applications/GLKB Cite.app` with the `+` button and enable it.
4. Reopen GLKB Cite.

PDFs made only of scanned images do not contain selectable text and require OCR
before GLKB Cite can use them.

### The API key cannot be saved

Run the installed copy from `/Applications`, not from the DMG. Open Settings
from the menu-bar icon and try saving again. If an old development identity left
a stale item, remove the `org.glkb.cite` generic password in Keychain Access and
save again. Never send the key in a bug report or screenshot.

### Settings does not open

Use the GLKB menu-bar icon and choose **Settings…**. If the window is behind
another app, choose the item a second time; the app activates and brings the
existing settings window forward.

## Upgrade and uninstall

To upgrade, quit GLKB Cite and replace it in Applications with the newer,
consistently signed copy. To uninstall, quit the app and move it to Trash. The
Keychain item can be removed first in Settings or later in Keychain Access by
searching for `org.glkb.cite`.
