# GLKB Cite — Installation Guide

GLKB Cite is a menu-bar app for macOS. Select a scientific sentence in any
app, click the badge (or press `⌥⌘G`), and it returns PubMed literature
evidence you can cite. This guide covers installing a test build, first-run
setup, everyday use, and troubleshooting.

## Requirements

- macOS 13 Ventura or later. The build is universal (Apple silicon and Intel).
- A GLKB API key (it starts with `glkb_`). Ask the GLKB team if you do not
  have one.
- The disk image, for example `GLKB Cite 0.2.0.dmg`.

## 1. Install

1. Quit any older GLKB Cite build, and quit GLKB Lens if you use it (it
   registers the same `⌥⌘G` shortcut).
2. Double-click the `.dmg`.
3. Drag **GLKB Cite** onto the **Applications** shortcut in the window.
4. Eject **GLKB Cite Installer**.
5. Open **GLKB Cite** from `/Applications` (not the copy inside the disk
   image). It appears as a GLKB icon in the menu bar; there is no Dock icon.

### If macOS says the app "is damaged and can't be opened"

Test builds are not yet notarized by Apple, and any download carries macOS's
quarantine flag. Together those produce a misleading "damaged" message —
nothing is actually damaged — and on macOS 15 Sequoia and later there is no
**Open Anyway** button for this case. Remove the quarantine flag yourself.

Preferably, run this on the disk image **before** opening it (adjust the path
if your download went elsewhere), then install as above:

```bash
xattr -d com.apple.quarantine ~/Downloads/"GLKB Cite 0.2.0.dmg"
```

If you already dragged the app to Applications, clear it there instead:

```bash
xattr -dr com.apple.quarantine "/Applications/GLKB Cite.app"
```

Only do this for a build you received directly from the GLKB Cite team.
Notarized releases will open with a plain double-click and need none of this.

## 2. First launch: the setup wizard

A four-step window opens the first time GLKB Cite runs.

1. **Welcome** — read the overview and click **Continue**.
2. **Allow selected-text access** — click **Request Access**. macOS shows a
   dialog; choose **Open System Settings**, enable **GLKB Cite** in
   *Privacy & Security → Accessibility*, then return to the wizard. It
   notices the change by itself and shows "Access granted". (Accessibility is
   how the app reads the text you selected in another app. It never reads
   password or other secure fields.)
3. **Store your GLKB key** — paste your `glkb_` key and click **Save**, then
   **Continue**. The key is stored only in your macOS Keychain and sent only
   to the GLKB endpoint.
4. **Compatibility Capture and privacy** — read the disclosure and click
   **Finish Setup**. (The button stays disabled until steps 2 and 3 are
   complete.)

If macOS asks *"GLKB Cite wants to use your confidential information stored in
org.glkb.cite"*, click **Always Allow**. This is the Keychain protecting your
API key; it appears after upgrades because the app binary changed.

## 3. Everyday use

### Find citations

- **Badge:** select a sentence with the mouse. A blue GLKB badge appears just
  above-right of the cursor. Click it. The badge disappears on its own after
  a few seconds, or as soon as you click elsewhere, type, or scroll.
- **Hot key:** select text and press `⌥⌘G`.
- **Menu:** select text, then choose **Find Citations** from the GLKB
  menu-bar icon.
- **Services:** in apps that support it, choose **Find Citations with GLKB
  Cite** from the app's *Services* menu.

Selections must be one scientific sentence of roughly 10–1000 characters.
Nothing is sent to GLKB until you click the badge or invoke one of the
commands above.

### The results panel

The panel opens at the top-right corner of the display you are working on.
Drag it anywhere by its header, like any window; it stays where you put it
while it remains open. Press **Esc** or click **✕** to close it.

- References are grouped into **Direct evidence** and **Indirect context**,
  numbered, with authors, year, journal, and a supporting excerpt you can
  expand.
- Click a reference's **PMID** to open it on PubMed.
- Hover over a reference and click **Cite** to get MLA, APA, Chicago,
  Harvard, and Vancouver renderings — click any of them to copy it — plus
  **BibTeX** and **EndNote** (RIS) exports.
- **Copy Plain Text** and **Copy Rich Report** copy the whole result list for
  pasting into notes or a document.

Always verify each source before citing; GLKB Cite is a research aid, not a
clinical decision tool.

### PDF viewers and other apps without accessible text

Some apps (PDF Expert and several other PDF viewers, drawing canvases) do not
expose selected text to macOS Accessibility. When **Allow temporary Copy
fallback** is enabled (Settings → Privacy; the wizard turns it on), GLKB Cite
still offers a badge after a deliberate drag or double-click in such an app.
Only when you click that badge does it briefly issue *Copy* to read the
selection, then restore your previous clipboard. `⌥⌘G` and the menu command
use the same fallback. Clipboard-history utilities may record the temporary
value; turn the fallback off if that matters to you.

## 4. Settings

Open **Settings…** from the menu-bar icon (or press `⌘,` while the menu is
open).

- **General** — show or hide the automatic selection badge, see the `⌥⌘G` hot
  key, and enable *Launch at login*.
- **Literature** — replace the API key (the field shows the stored key
  masked), include or omit evidence excerpts, and set how long results are
  cached in memory (Off, 5 min, 15 min, 1 hour). The cache is cleared when the
  app quits.
- **Privacy** — turn the temporary Copy fallback on or off and review what
  leaves your Mac.

## 5. Upgrading

Quit GLKB Cite, replace the app in Applications with the new copy, and launch
it. Because test builds are not signed with a persistent identity, macOS
treats each new build as a different app:

- Accessibility access must be granted again. The app asks at launch; if it
  does not, open *Privacy & Security → Accessibility*, remove the old GLKB
  Cite entry, click **+**, add `/Applications/GLKB Cite.app`, and enable it.
- The Keychain asks once for permission to read the stored key: **Always
  Allow**.

Your settings and API key are kept across upgrades.

## 6. Troubleshooting

### The badge does not appear when I select text

1. Check that **Show Selection Badge** is ticked in the menu-bar menu.
2. Check that **GLKB Cite** is enabled and points at `/Applications/GLKB
   Cite.app` in *Privacy & Security → Accessibility*. After an upgrade the
   toggle can look enabled while being stale — remove and re-add it.
3. Select with a real drag or a double-click; a single click never triggers
   the badge.
4. In a PDF viewer or similar app, make sure **Allow temporary Copy fallback**
   is on (Settings → Privacy).
5. `⌥⌘G` works even when the badge cannot, so use it as a fallback.

To see exactly why a capture failed, turn on diagnostics (they record element
types and error codes only — never the selected text), reproduce, then read
the log:

```bash
defaults write org.glkb.cite diagnostics.captureLoggingEnabled -bool true
```

```bash
/usr/bin/log show --last 5m --info --predicate 'subsystem == "org.glkb.cite"'
```

Turn diagnostics off again with the same command and `-bool false`. Scanned
PDFs made only of page images contain no selectable text; run OCR first.

### `⌥⌘G` does nothing

Another app owns the shortcut, most likely GLKB Lens. Quit it and relaunch
GLKB Cite. Settings → General notes when the shortcut could not be registered.

### "GLKB rejected this API key"

The stored key is inactive or mistyped. Open Settings → Literature, paste a
current `glkb_` key, and click **Save**. Never send a key in a bug report or
screenshot.

### "No citation result is available yet"

GLKB found no structured PubMed references for that sentence. Try a more
specific sentence containing a clear scientific claim.

### The results panel opened on another display or off to the side

It always opens at the top-right of the display where the selection was made.
If you have dragged it, it keeps that position until closed; close it with
**Esc** and search again to reset.

## 7. Uninstall

Quit GLKB Cite and move `/Applications/GLKB Cite.app` to the Trash. To remove
your API key, open Keychain Access and delete the `org.glkb.cite` item. To
remove preferences, run:

```bash
defaults delete org.glkb.cite
```

## Privacy in brief

The selected text is sent to the GLKB endpoint only when you ask for
citations. The API key lives in your Keychain. Results may be cached in memory
until the app quits. There are no analytics and no history of your queries.
See `PRIVACY.md` in the repository for the full notice.
