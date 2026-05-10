<p align="center">
  <img src="logo.svg" alt="codehunt logo" width="160" height="160">
</p>

<h1 align="center">codehunt</h1>

<p align="center">
  Find currently-working coupon codes for any URL or domain, ranked by confidence.
  <br>Two surfaces — Android app and CLI — sharing one prompt and parser.
</p>

<p align="center">
  <a href="https://github.com/DazedDingo/codehunt/releases/latest">Download APK</a> ·
  <a href="#cli">CLI</a>
</p>

---

Not a Honey replacement — it can't auto-apply at checkout. It's an on-demand
researcher: ask it about a domain, get a confidence-ranked list of codes you
can paste yourself.

## Surfaces

| Surface  | Best for                                     | Where it lives                |
| -------- | -------------------------------------------- | ----------------------------- |
| Android  | Phone checkout. Share URL from Chrome.       | [`app/`](app)                 |
| CLI      | Scripts, automation, quick desktop lookups.  | [`codehunt.py`](codehunt.py)  |

## Android app

1. Grab the APK from the [latest release](../../releases/latest) and sideload
   it (Settings → Apps → Allow from this source).
2. From now on, when you're on a checkout page in Chrome: tap the URL bar's
   Share button, pick **codehunt**, and the hunt starts automatically. You
   can also type a URL on the home screen directly.

No setup, no API keys, no backend — the Gemini key is baked into the build via
a CI secret. The about screen (info icon, top right) shows the installed
version + DazedDingo signature.

### A note on the baked-in key

The Gemini key in the APK is a free-tier AI Studio key with a 1500
requests/day cap, no cost. The APK is public on Releases, so anyone who
downloads it shares that quota. Worst case: hit the daily limit, rotate
the secret in GitHub, push a new tag. If you'd rather host your own key,
clone the repo and rebuild with `flutter build apk --dart-define=GEMINI_API_KEY=...`.

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

## Provider trade-offs

| Provider | Where               | Cost / query | Daily cap   | Notes                                                                          |
| -------- | ------------------- | ------------ | ----------- | ------------------------------------------------------------------------------ |
| Gemini   | App + CLI default   | $0           | ~1500/day   | Free-tier Flash + Google Search grounding. JSON parsed loosely from prose.     |
| Claude   | CLI only            | ~$0.03–0.08  | rate-limit  | Sonnet 4.6 + `web_search`. Schema-enforced JSON via structured outputs.        |

## How it works

1. Strip the URL down to a bare domain.
2. Send one prompt to the chosen LLM with a web-search tool enabled, asking
   for codes from multiple sources with a confidence score.
3. Return JSON. CLI prints it, app renders it.

The whole thing is one model call per query.

## Why this design

- **One LLM call, not a scraper farm.** Coupon aggregators block scrapers and
  rotate their HTML. A grounded LLM gets across that without selectors.
- **No backend.** Earlier versions had a FastAPI proxy. v0.3.0 dropped it —
  the app calls Gemini directly and the key ships in the APK. Simpler to
  install, simpler to operate, no Linux box to maintain.
- **No database.** Codes go stale fast; live querying is the right move.

## Honest limitations

- LLMs sometimes surface fabricated codes from low-quality aggregator sites.
  Treat "low" confidence as "probably won't work."
- Boutique merchants often genuinely have no public codes. An empty result is
  real information, not a failure.
- Doesn't handle codes that are account-gated, region-gated, or
  first-purchase-only.
- Gemini's free tier has a 1500 req/day cap per key, shared across everyone
  who installs the public APK.

## Development

```bash
pip install ruff
ruff check codehunt.py tests/ scripts/
python -m unittest discover -s tests -v
```

CI runs Python lint + tests on push/PR (Python 3.10–3.13), and builds the
Android APK in a separate workflow — rasterizing the logo into launcher
icons and injecting the Gemini key via `--dart-define` from a repo secret.

## Releases

Tagged releases live on the [Releases page](../../releases). Each one lists
user-visible changes in plain English and ships a `codehunt-vX.Y.Z.apk` you
can install directly. See [CHANGELOG.md](CHANGELOG.md) for the full history.

## License

[MIT](LICENSE).
