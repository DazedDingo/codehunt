# Changelog

All notable changes to codehunt are documented here. Each release entry is
written as plain-English bullets — what changed and why it matters — not raw
commit subjects.

## v0.1.0 — 2026-05-10

The first release.

- Look up working coupon codes for any URL or bare domain. URLs get stripped
  to the registrable host (`https://www.example.com/checkout` → `example.com`)
  before searching.
- Defaults to **Gemini 2.5 Flash** with Google Search grounding — free tier,
  ~1500 requests/day per API key.
- Optional `--provider claude` switches to **Claude Sonnet 4.6** with
  `web_search` (paid, ~$0.03–$0.08/query). Gives schema-enforced JSON output
  via structured outputs.
- Confidence ranking (high / medium / low) sorts results so the most
  likely-to-work codes show first.
- `--json` flag emits raw JSON for piping into other tools.
- `--version` flag and a `codehunt vX.Y.Z` line at the top of human-readable
  output, so screenshots and bug reports always include the version.
