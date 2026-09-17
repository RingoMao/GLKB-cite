# GLKB Cite privacy notice

GLKB Cite has no app analytics or telemetry. It does not intentionally log
selected text, API responses, citation content, or credentials.

When the user explicitly requests citations, the selected text and requested
reference count are sent to:

`https://jieliulab3.dcmb.med.umich.edu/reorg-api/api/v1/api-key-agent/cite`

The user-provided GLKB API key is stored only in macOS Keychain and sent to this
HTTPS endpoint as a Bearer credential. Completed results can be cached in memory
for the configured interval and are discarded when the app exits. Non-secret
preferences are stored in macOS user defaults.

Accessibility capture reads the active selection without touching the general
clipboard. If Compatibility Capture is enabled and Accessibility cannot expose
a selection, GLKB Cite may temporarily invoke Copy, inspect the copied text, and
restore every materializable clipboard representation. Clipboard managers may
record that temporary value. GLKB Cite will not overwrite a newer clipboard
change, and it will not send a request if safe restoration cannot complete.
The Copy fallback runs only for explicit invocations that go through selection
capture: the hot key, the Find Citations menu command, or clicking the selection
badge. The macOS Service never uses it; the Service receives the selected text
directly from the Services pasteboard. The badge itself
is offered from Accessibility alone; in an app that exposes no selected text
(for example some PDF viewers) it appears after a deliberate drag or
double-click, and the temporary Copy happens only if you then click it.

Before public distribution, the publisher must document the GLKB service
operator, privacy contact, server-side retention period, deletion process, and
handling of selected text, account metadata, IP addresses, and request logs. If
the service retains data beyond servicing the request, update this notice and
`PrivacyInfo.xcprivacy` before release.

GLKB Cite is a literature research assistant, not a clinical decision system.
Verify every source before citation, publication, or clinical use.
