# GLKB Cite privacy notice

GLKB Cite has no app analytics or telemetry. It does not log selected text,
API responses, citation content, or credentials.

## What leaves your Mac, and when

**Citation requests.** Only when you ask for citations (clicking the selection
badge, pressing `⌥⌘G`, choosing *Find Citations*, or using the macOS Service)
the selected text and the requested reference count are sent over HTTPS to:

`https://jieliulab3.dcmb.med.umich.edu/reorg-api/api/v1/api-key-agent/cite`

The request carries your GLKB API key as a Bearer credential, `Content-Type`
and `Accept` headers, and the system's default `User-Agent` header, which names
the app (`GLKBCiteMac`), its build number, and the CFNetwork and macOS
versions. No account name, device identifier, or other data is sent. The app
refuses to follow HTTP redirects, so the text can only reach the host above.

**Update checks.** Release builds that ship with an update feed contact that
feed over HTTPS at launch and periodically to look for a newer version
(Sparkle). Those requests carry the app version and macOS version; they are
not linked to you. Test builds have no feed and never check for updates.

Nothing else connects to the network. PubMed links open in your browser only
when you click them.

## What stays on your Mac

- **API key:** stored only in the macOS Keychain (service `org.glkb.cite`,
  this device only, never synced to iCloud Keychain).
- **Results:** cached in memory for the interval you choose (off by default
  after setup is "15 minutes"; at most one hour) and discarded when the app
  quits. Cache entries are keyed by a hash, never by the sentence itself.
- **Preferences:** non-secret settings live in macOS user defaults
  (`org.glkb.cite`).
- **Diagnostics (off by default):** when you turn capture diagnostics on, the
  unified log records which capture strategy ran, element roles, character
  counts, error codes, and the bundle identifier of the app you selected text
  in. Selected text is never logged.

## What the app observes locally

**Accessibility.** With your permission, GLKB Cite uses the macOS
Accessibility API to read the text currently selected in the frontmost app,
and only that text, at the moment you invoke it. It never reads password or
other secure fields. The text stays in memory and is sent nowhere until you
ask for citations.

**Selection badge (optional).** When *Show Selection Badge* is on, the app
registers a system-wide mouse monitor that receives left-button down, drag and
up events and scroll events from every app: the pointer position, click count
and modifier keys, nothing about the content under the pointer. It uses them
only to notice that a selection gesture ended. After such a gesture it reads
the selection through Accessibility, locally, to decide whether to offer a
badge, and keeps that text in memory only while the badge is on screen (at
most about nine seconds). While a badge is showing, a keyboard monitor notices
that *some* key was pressed so the badge can disappear; it does not receive
which key, and it is removed as soon as the badge is gone. No monitor is
installed while the badge feature is off.

**Temporary Copy fallback (optional, off unless you turn it on).** Some apps
(several PDF viewers, for instance) do not expose their selection to
Accessibility. If you have enabled *Allow temporary Copy fallback* in the setup
wizard or Settings → Privacy, and only when you explicitly ask for citations
(badge click, `⌥⌘G`, or the menu command; never on the passive badge path and
never from the macOS Service), GLKB Cite briefly issues *Copy* to the
frontmost app, reads the copied text, and restores your previous clipboard
contents. It refuses to run when the clipboard holds data marked concealed or
transient (as password managers mark their items) or file promises, it never
overwrites a newer clipboard change, it keeps watching for a late *Copy* for a
few seconds after a timeout so the restore still happens, and it does not send
a request if the restore cannot complete. Clipboard-history utilities may still
record the temporary value.

## Before public distribution

The publisher must document the GLKB service operator, privacy contact,
server-side retention period, deletion process, and handling of selected text,
account metadata, IP addresses, and request logs. If the service retains data
beyond servicing the request, update this notice and `PrivacyInfo.xcprivacy`
before release.

GLKB Cite is a literature research assistant, not a clinical decision system.
Verify every source before citation, publication, or clinical use.
