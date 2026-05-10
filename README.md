<p align="center">
  <img src="logo.svg" alt="codehunt logo" width="160" height="160">
</p>

<h1 align="center">codehunt</h1>

<p align="center">
  A small CLI that takes a URL or domain and asks an LLM to web-search for
  currently-working coupon codes, then prints them ranked by confidence.
</p>

Defaults to **Gemini 2.5 Flash** with Google Search grounding (free tier,
~1500 requests/day). Optional `--provider claude` switches to Claude
Sonnet 4.6 with `web_search` (paid, ~$0.03–$0.08/query).

Not a Honey replacement — it can't auto-apply at checkout. Think of it as
a focused, on-demand researcher for the times you're already on a checkout
page wondering if a code exists.

## Setup

```bash
cd codehunt
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export GEMINI_API_KEY=AIza...
```

For the optional Claude path:

```bash
pip install anthropic
export ANTHROPIC_API_KEY=sk-ant-...
```

## Usage

```bash
python codehunt.py thegainsboroughbathspa.co.uk          # gemini (default)
python codehunt.py example.com --provider claude         # claude
python codehunt.py example.com --json                    # raw JSON for piping
```

## How it works

1. Strips the URL down to a bare domain.
2. Sends one prompt to the chosen LLM with a web-search tool enabled,
   asking for codes from multiple sources with a confidence score.
3. Parses the JSON response and prints results sorted by confidence.

The whole thing is one model call.

## Provider trade-offs

| Provider | Cost / query | Daily cap   | Notes                                                                          |
| -------- | ------------ | ----------- | ------------------------------------------------------------------------------ |
| Gemini   | $0           | ~1500/day   | Free-tier Flash + Google Search grounding. JSON parsed loosely from prose.     |
| Claude   | ~$0.03–0.08  | rate-limit  | Sonnet 4.6 + `web_search`. Structured outputs, so JSON is guaranteed-shaped.   |

In practice Gemini is fine for this task. Use Claude when you want the
schema-enforced output (e.g. piping into a strict downstream parser) or
when Gemini's grounding misses a result you know exists.

## Why this design

- **One LLM call, not a scraper farm.** Coupon aggregator sites actively
  block scrapers and rotate their HTML. A grounded LLM gets across that
  without you maintaining selectors.
- **JSON-only output.** Lets you pipe into anything (a Flutter app, a
  notification script, a clipboard manager).
- **No database.** Codes go stale fast; querying live is the right move.
- **Provider-pluggable.** Hosted LLMs change pricing and quality; the
  `--provider` switch lets you re-evaluate without rewriting.

## Extending it

In rough order of effort:

1. **Wrap as an HTTP API.** ~20 lines of FastAPI. Host on your Oracle box,
   call from a Flutter screen in your existing app.
2. **Cache by domain for ~6 hours.** Same domain queried twice in a day
   shouldn't re-search. Redis or just SQLite.
3. **Browser test step.** Use Playwright to actually try each code on the
   real checkout page and report which ones applied. This is the hard part
   — every site's checkout is bespoke. Worth it only for sites you hit
   often.
4. **Background watcher.** Cron job that re-queries your top 10 stores
   weekly and pushes a notification when a new high-confidence code appears.
5. **Browser extension.** Manifest V3 extension that calls your API when
   it detects a coupon field on a checkout page. Most useful end state, but
   significantly more work than the CLI.

## Honest limitations

- LLMs will sometimes invent plausible-looking codes if real ones are
  scarce. The confidence scoring helps but isn't perfect — treat "low"
  confidence as "probably won't work."
- For boutique merchants (like the Gainsborough), public promo codes
  rarely exist. The tool will correctly return an empty list more often
  than not for those, which is itself useful information.
- Doesn't handle sites where the discount is account-gated, region-gated,
  or first-purchase-only.
- Gemini's free tier has a 1500 req/day organization-wide cap. If you
  share the key across projects, plan accordingly.

## Releases

Tagged releases live on the
[Releases page](../../releases). Each release page lists the user-visible
changes in plain English — see [CHANGELOG.md](CHANGELOG.md) for the full
history.

`codehunt --version` prints the installed version, and the version is
shown at the top of human-readable output too — handy for bug reports.

## Development

Run lint + tests locally the same way CI does:

```bash
pip install ruff
ruff check codehunt.py tests/
python -m unittest discover -s tests -v
```

CI runs on every push and PR across Python 3.10 / 3.11 / 3.12 / 3.13. Tests
cover pure functions (`extract_domain`, `_parse_json_loose`) and the CLI
surface (`--version`, `--help`, missing-credential paths). No live API calls.

## License

[MIT](LICENSE).
