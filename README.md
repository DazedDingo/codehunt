<p align="center">
  <img src="logo.svg" alt="codehunt logo" width="160" height="160">
</p>

<h1 align="center">codehunt</h1>

<p align="center">
  Find currently-working coupon codes for any URL or domain, ranked by confidence.
  <br>Three surfaces — Android app, CLI, and a self-hostable backend — sharing one core.
</p>

<p align="center">
  <a href="https://github.com/DazedDingo/codehunt/releases/latest">Download APK</a> ·
  <a href="#cli">CLI</a> ·
  <a href="backend/README.md">Backend</a>
</p>

---

Not a Honey replacement — it can't auto-apply at checkout. It's an on-demand
researcher: ask it about a domain, get a confidence-ranked list of codes you
can paste yourself.

## Surfaces

| Surface  | Best for                                     | Where it lives                |
| -------- | -------------------------------------------- | ----------------------------- |
| Android  | Phone checkout. Shares URL from Chrome.      | [`app/`](app)                 |
| CLI      | Scripts, automation, quick desktop lookups.  | [`codehunt.py`](codehunt.py)  |
| Backend  | What the app talks to. Self-host, one box.   | [`backend/`](backend)         |

All three call the same `hunt_gemini` / `hunt_claude` functions, so behavior
is identical regardless of how you invoke them.

## Android app

1. Stand up the [backend](backend/README.md) on a Linux box you control. It
   needs a `GEMINI_API_KEY` and a token you make up.
2. Grab the APK from the [latest release](../../releases/latest) and sideload
   it (Settings → Apps → Allow from this source).
3. Open the app, tap the gear icon, paste your backend URL and token. Save.
4. From now on, when you're on a checkout page in Chrome: tap the URL bar's
   Share button, pick **codehunt**, and the hunt starts automatically.

The app's Settings screen shows the installed version (and the DazedDingo
signature, in case you forget what you're running).

## CLI

```bash
git clone https://github.com/DazedDingo/codehunt.git
cd codehunt
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export GEMINI_API_KEY=AIza...

python codehunt.py thegainsboroughbathspa.co.uk          # gemini (default)
python codehunt.py example.com --provider claude         # claude (paid)
python codehunt.py example.com --json                    # raw JSON for piping
python codehunt.py --version
```

For the optional Claude path: `pip install anthropic` and
`export ANTHROPIC_API_KEY=...`.

## Backend

A thin FastAPI proxy. Deployment notes, endpoint reference, and the systemd
unit live in [`backend/README.md`](backend/README.md).

## Provider trade-offs

| Provider | Cost / query | Daily cap   | Notes                                                                          |
| -------- | ------------ | ----------- | ------------------------------------------------------------------------------ |
| Gemini   | $0           | ~1500/day   | Free-tier Flash + Google Search grounding. JSON parsed loosely from prose.     |
| Claude   | ~$0.03–0.08  | rate-limit  | Sonnet 4.6 + `web_search`. Structured outputs, so JSON is guaranteed-shaped.   |

In practice Gemini is fine. Use Claude when you want schema-enforced output or
when Gemini's grounding misses a result you know exists.

## How it works

1. Strip the URL down to a bare domain.
2. Send one prompt to the chosen LLM with a web-search tool enabled, asking
   for codes from multiple sources with a confidence score.
3. Return JSON. CLI prints it, app renders it, backend forwards it.

The whole thing is one model call per query.

## Why this design

- **One LLM call, not a scraper farm.** Coupon aggregators block scrapers and
  rotate their HTML. A grounded LLM gets across that without selectors.
- **Provider-pluggable.** LLMs change pricing and quality; the `--provider`
  switch lets you re-evaluate without rewriting.
- **Three surfaces, one core.** `extract_domain`, `hunt_gemini`, `hunt_claude`
  live in `codehunt.py` and are imported by everything else. No duplication.
- **No database.** Codes go stale fast; live querying is the right move.

## Honest limitations

- LLMs sometimes surface fabricated codes from low-quality aggregator sites.
  Treat "low" confidence as "probably won't work."
- Boutique merchants often genuinely have no public codes. An empty result is
  real information, not a failure.
- Doesn't handle codes that are account-gated, region-gated, or
  first-purchase-only.
- Gemini's free tier has a 1500 req/day cap per organization.

## Development

```bash
pip install ruff
ruff check codehunt.py tests/ backend/ scripts/
python -m unittest discover -s tests -v

# Backend, locally:
GEMINI_API_KEY=... CODEHUNT_API_TOKEN=dev .venv/bin/uvicorn backend.server:app --reload
```

CI runs Python lint + tests on push/PR (Python 3.10–3.13), and builds the
Android APK in a separate workflow on every `app/` change.

## Releases

Tagged releases live on the [Releases page](../../releases). Each one lists
user-visible changes in plain English and ships a `codehunt-vX.Y.Z.apk` you
can install directly. See [CHANGELOG.md](CHANGELOG.md) for the full history.

`codehunt --version` (CLI) and the Settings screen (app) both display the
installed version — handy for bug reports.

## License

[MIT](LICENSE).
