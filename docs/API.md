# GLKB citation API integration

GLKB Cite currently targets one citation-only endpoint:

`POST https://jieliulab3.dcmb.med.umich.edu/reorg-api/api/v1/api-key-agent/cite`

## Request

```json
{
  "text": "Loss-of-function mutations in PCSK9 lower LDL cholesterol.",
  "max_references": 5
}
```

- `text`: required string, 10–1000 characters; use one scientific sentence.
- `max_references`: requested result count. The app always requests 5; the value is not user-configurable.
- Header: `Authorization: Bearer <user-supplied glkb_ key>`. The key must be
  `glkb_` followed by ASCII letters, digits, `-` or `_` on a single line; the
  client refuses anything else before sending (a key with an embedded line
  break would otherwise be sent with no `Authorization` header at all).
- Other headers: `Content-Type: application/json`, `Accept: application/json`,
  and the system default `User-Agent`.
- Client timeout: 90 seconds. TLS 1.2 or later is required.

Do not send older QA fields such as prompt, ranking, review filters, or HIRN
mode. The endpoint rejects unknown request fields.

## Transport policy

- **Redirects are never followed.** A 3xx answer is reported as a failed
  request; the client also checks that the final response came from the
  endpoint's host. A redirected POST would re-send the user's text elsewhere
  (CFNetwork strips the Bearer header on redirect, so it could never succeed
  anyway).
- **One retry** after a jittered ~0.6–0.9 s pause for `502`, `503` and `504`;
  every other status is final. Each attempt is billed, so the client never
  retries more than once.
- **`429`:** the `Retry-After` header (seconds), when present, becomes the
  user-facing advice.
- **Success bodies** must be JSON (`Content-Type` containing `json`, when the
  header is present) and at most 2 MiB; anything else is a malformed response.
- Server error text (`detail` / `message` / `error`, or a validation array of
  `msg`) is shown only for `4xx` statuses, with control characters removed and
  the message cut to 200 characters. `5xx` bodies are never shown.

## Success response

```json
{
  "status": "ok",
  "query": "…",
  "references": [
    {
      "pmid": "12345678",
      "title": "Example title",
      "url": "https://pubmed.ncbi.nlm.nih.gov/12345678/",
      "n_citation": 42,
      "date": "2024",
      "journal": "Example Journal",
      "authors": ["A Author", "B Author"],
      "evidence": ["Supporting excerpt"],
      "why": "Why this article supports the selected sentence"
    }
  ],
  "diagnostics": {
    "elapsed_ms": 1200
  }
}
```

`status: "no_results"` with an empty `references` array is also a successful,
terminal response. `status: "ok"` without any usable reference, or
`no_results` with references, is treated as malformed.

Reference normalisation:

- A reference needs a non-empty title and a PubMed identifier from `pmid`,
  `pubmedid`, or the PMID inside a `pubmed.ncbi.nlm.nih.gov/<n>/` URL. A
  generic `id` field is not a PMID. PMIDs must be ASCII digits; leading zeros
  are dropped, so `0042` and `42` are the same article and are deduplicated.
- The app always links the canonical `https://pubmed.ncbi.nlm.nih.gov/<pmid>/`
  URL; a server-supplied `url` is never opened.
- `n_citation` (or the legacy `citation_count`) is kept only when it is a
  whole number between 0 and 10,000,000; anything else is shown as absent.
- JSON booleans are never treated as text or numbers.
- At most 500 raw entries are scanned for the five usable references.

## Errors

- `401`: missing or invalid key
- `403`: inactive or unauthorized key
- `422`: selection/request validation failure
- `429`: usage or rate limit reached (see `Retry-After` above)
- `502` / `503` / `504`: transient upstream failure (retried once)

The server error body may contain a string `detail` or a validation-detail
array. The app extracts a user-facing message but never includes its credential
in errors or logs.

## Testing rule

Automated and routine development tests must use fixtures and injected
`URLSession` protocols. Live requests require explicit team approval and must
never use a credential committed to the repository.
