# Changelog

All notable changes to codehunt are documented here. Each release entry is
written as plain-English bullets — what changed and why it matters — not raw
commit subjects.

## v0.2.0 — 2026-05-10

The mobile release.

- **Android app.** Native Flutter app you sideload from the Releases page.
  Enter a URL or share one to it from Chrome and it queries your backend.
  Settings screen shows the installed version + DazedDingo signature.
- **Share-to-codehunt.** When you're on a checkout page in Chrome, tap Share
  → codehunt. The URL pre-fills and the hunt runs automatically. Cuts the
  whole "type a domain into a CLI" friction the v0.1 design had on mobile.
- **Backend (`backend/`).** Thin FastAPI proxy that lives on a Linux box you
  control. The Gemini key stays on the server; the app talks to it with a
  bearer token you generate. Reuses the CLI's `hunt_gemini` / `hunt_claude`
  functions so all three surfaces behave identically. Ships with a systemd
  unit and a deploy guide.
- **APK built and attached automatically on every tagged release.** GitHub
  Actions builds `codehunt-vX.Y.Z.apk` and uploads it to the Release page —
  no manual builds.
- **Lint widened to cover `backend/` and `scripts/`** in the existing CI.

### Migration from v0.1.0

CLI users — nothing to do. `codehunt.py` interface is unchanged. New apps
(backend + Android) are additive.

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
- GitHub Actions CI on every push and PR: lint with `ruff` + unit tests on
  Python 3.10 / 3.11 / 3.12 / 3.13. No live API calls in CI; pure functions
  and CLI surface only.
