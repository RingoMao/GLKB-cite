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
- `max_references`: requested result count. The app exposes 3, 5, and 10.
- Header: `Authorization: Bearer <user-supplied glkb_ key>`.
- Client timeout: 90 seconds.

Do not send older QA fields such as prompt, ranking, review filters, or HIRN
mode. The endpoint rejects unknown request fields.

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
terminal response. GLKB Cite ignores malformed references, requires numeric
PMIDs and non-empty titles, creates canonical PubMed URLs, and deduplicates by
PMID. `status: "ok"` without any usable reference is treated as malformed.

## Errors

- `401`: missing or invalid key
- `403`: inactive or unauthorized key
- `422`: selection/request validation failure
- `502`: transient upstream failure
- `504`: upstream timeout

The server error body may contain a string `detail` or a validation-detail
array. The app extracts a user-facing message but never includes its credential
in errors or logs.

## Testing rule

Automated and routine development tests must use fixtures and injected
`URLSession` protocols. Live requests require explicit team approval and must
never use a credential committed to the repository.
