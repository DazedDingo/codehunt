# Changelog

All notable changes to codehunt are documented here. Each release entry is
written as plain-English bullets — what changed and why it matters — not raw
commit subjects.

## v0.9.0 — 2026-05-22

Persistence + smarter ranking + deep-link entry.

- **Confidence filter persists.** Your last filter choice (`high` /
  `medium+` / `all`) is now remembered across launches via
  `SharedPreferences`.
- **Tap-behavior toggle.** New switch on the About screen: "Tap a code
  opens detail sheet". On (default): tap = copy + sheet. Off: tap = copy
  + snackbar, and each row gets an info icon that opens the sheet.
- **Re-rank via prompt.** When a domain has thumbs-down feedback on
  previous codes, the prompt now explicitly tells the model not to
  surface those codes again — steers it toward genuinely-new alternatives
  rather than just hiding rejected ones post-hoc.
- **`codehunt://` deep link.** New URI scheme:
  - `codehunt://hunt?url=https://example.com` — URL-encoded form
  - `codehunt://example.com/checkout` — plain form
  Both auto-fill the home screen and run the hunt. Works from Tasker,
  Android Shortcuts, browser bookmarks, or any automation that fires
  ACTION_VIEW intents.
- **`Clear history & cache` now preserves settings** — your tap-behavior
  toggle and filter pref survive a reset.

### Tests

- `app/test/storage_test.dart` gains preference round-trip tests and a
  `clearAll preserves preferences` test pinning the new semantic.

### Migration from v0.8.0

In-place update — same signing key, same storage format additively
extended.

## v0.8.0 — 2026-05-20

Locale awareness + personal feedback loop. Plus dark theme default.

- **Locale-aware prompting.** The domain's TLD (`.co.uk`, `.de`, `.com.au`,
  …) now feeds a region + currency hint into the Gemini/Claude prompt.
  UK shoppers should see noticeably less US-centric noise on `.co.uk`
  sites; results lean on regional aggregators (hotukdeals, mydealz, etc.)
  and format discounts in local currency where it matters. Applies to
  both app and CLI.
- **Worked / didn't-work feedback.** Detail bottom sheet now has 👍 / 👎
  buttons. Tracked locally per (domain, code). On future hunts of the same
  domain:
  - 👍 codes float to the top of the list with a small green `worked`
    badge, and the avatar becomes a check icon.
  - 👎 codes sink to the bottom with strikethrough + a close icon avatar.
  No API spend.
- **Dark theme default.** App now forces dark mode (`ThemeMode.dark`).
  Audited hardcoded greys/blues in the result tiles and detail sheet —
  the "cached" badge, source-link blue, source-context blockquote, and
  empty-state text all use Material 3 scheme colors now.
- **About → Clear history & cache** also clears the feedback store.

### Tests

- New `tests/test_codehunt.py::TestLocaleHint` covers TLD → region mapping
  including compound TLDs (`.co.uk`, `.com.au`) and unknown fall-through.
- New `app/test/storage_test.dart` covers feedback round-trip, domain
  isolation, pinning, and `clearAll` semantics.

### Migration from v0.7.0

In-place update — same signing key. Existing cached results don't carry
context yet; pull-to-refresh on a cached domain to repopulate.

## v0.7.0 — 2026-05-11

The "is this code legit?" release.

- **Schema gains a `context` field.** Each result now carries 1-2
  sentences quoted or paraphrased from the source page showing where the
  code was found and any terms (expiry, minimum spend). Applies to both
  the app and the CLI.
- **Tap a code → detail bottom sheet.** Replaces the old snackbar. Shows
  the code in large monospace, the discount, the source context quote in
  a blockquote-style box, notes, the full source URL, and buttons to
  open the source page in your browser or copy the code again. Code is
  still copied to clipboard on the initial tap.
- **CLI prints the snippet** under each code as `quote: "..."` when
  available.

### Migration from v0.6.0

In-place update — same signing key. Cached results from v0.6.0 won't
have a context field (treated as empty string until refreshed). Pull
down to force a fresh hunt and pick up the context.

## v0.6.0 — 2026-05-10

Three more app polish features.

- **Pull-to-refresh.** Drag down on the result list and codehunt
  re-queries Gemini directly, bypassing the 1-hour cache. The standard
  Material `RefreshIndicator` shows the spinner until the new result
  comes back. Works even on empty/error states (empty list is still
  scrollable).
- **Domain pinning.** Long-press a history chip to pin/unpin it. Pinned
  domains float to the top of the chip row with a 📌 icon and stay
  there even when they fall outside the 20-entry recency cap. Good for
  the 3–4 sites you actually shop at regularly.
- **Cross-fade between hunts.** The result area now uses
  `AnimatedSwitcher` keyed by the pending Future, so when a new share
  comes in while you're looking at a previous result, the old result
  fades out and the spinner/new result fades in. Smoother feel for
  rapid share-from-Chrome flow.
- **About → Clear history & cache** also clears pins.

### Migration from v0.5.0

In-place update — same signing key, same storage format additively
extended (pinned list is a new key; existing history and cache carry
forward).

## v0.5.0 — 2026-05-10

Three more quality-of-life features in one release. Results are now both
*better* (junk filtered out) and *more verifiable* (tap a source to see
where it came from).

- **Junk-aggregator blocklist baked into the prompt.** Coupert, PromoPro,
  CouponBirds, CouponXoo, and DontPayFull are known to fabricate
  plausible-looking codes; the prompt now tells the model to discard codes
  sourced *only* from those sites unless a reputable source (RetailMeNot,
  Honey, Slickdeals, Reddit, the merchant directly) independently confirms.
  Applies to both the app and the CLI.
- **Tappable sources.** The `confidence · source` line under each code is
  now a link when the source looks like a URL or bare domain — taps open
  in your default browser. The prompt also now asks for fully-qualified
  URLs as sources whenever possible.
- **Confidence filter.** A segmented control above the results lets you
  pick `high` / `medium+` / `all`. Default is `medium+` so low-confidence
  noise is hidden by default; switch to `all` to see everything.
- **Empty-filter explainer.** If the filter hides every code, the screen
  tells you how many are filtered out and which option would reveal them.

### Migration from v0.4.0

In-place update — same signing key, same storage format. History and
cache carry forward.

## v0.4.0 — 2026-05-10

Three quality-of-life features in one release.

- **Search history.** Recent hunted domains show as horizontally-scrolling
  chips above the results area. Tap to re-hunt. Capped at 20, newest first.
  Persisted across launches.
- **Per-domain result cache (1-hour TTL).** Same domain queried within an
  hour returns the previous result instead of re-burning Gemini quota.
  Cached results show a small `cached` badge next to the domain so you know
  they're not live. If you want a fresh hunt, tap **Clear history & cache**
  on the About screen.
- **Tap a code to copy.** Single tap on any code in the result list copies
  it to the clipboard and shows a brief snackbar confirmation. A small copy
  icon on the right edge of each row reinforces the affordance. No more
  long-press selection dance.
- **About screen gained a "Clear history & cache" button.** Asks for
  confirmation before wiping.

### Migration from v0.3.1

In-place update — the stable v0.3.1 signing key carries forward. No
uninstall needed. Existing settings (none) are unaffected; history and
cache start empty on first launch.

## v0.3.1 — 2026-05-10

Critical fixes on top of v0.3.0.

- **Fixes "no address associated with hostname" on every search.** Flutter's
  `flutter create` only injects `<uses-permission android:name="android.permission.INTERNET" />`
  into the *debug* manifest, not the release one. So `release` builds shipped
  without internet permission — DNS resolved as "no such host" for every
  Gemini call. The manifest patcher now adds the permission explicitly.
- **Fixes "uninstall before update" on every release.** v0.3.0 was
  debug-signed with a fresh keystore on each CI run, so Android refused to
  recognize new APKs as upgrades of the existing install. v0.3.1 introduces
  a stable release-signing keystore stored as a GitHub Actions secret. From
  now on, future updates install in-place without uninstalling first.

### Migration

You'll need to uninstall v0.3.0 one more time, then install v0.3.1. Going
forward, v0.3.1 → v0.3.2 → v0.4.x will install over the top cleanly.

## v0.3.0 — 2026-05-10

The zero-setup release.

- **No more backend.** The app calls Gemini directly with a key baked in
  at build time via `--dart-define`. Install the APK, share a URL from
  Chrome, get results — no Linux box to maintain, no settings to fill in.
- **Settings screen → About screen.** No more "API base URL" / "API token"
  fields to confuse you. Just the logo, version, author, and source link.
- **Launcher icon works.** The repo's `logo.svg` is rasterized in CI by
  `librsvg`, then `flutter_launcher_icons` generates the Android mipmap
  set (legacy + adaptive). The home screen now shows the actual codehunt
  icon instead of the default Flutter robot.
- **Backend deleted.** The `backend/` directory and its FastAPI proxy are
  gone. If you want self-hosted key control, the git history still has it;
  the simpler default is now the canonical path.
- **CI secret.** The Gemini key lives as `GEMINI_API_KEY` in repo secrets,
  not in source. The APK still contains it (necessarily — it has to call
  the Gemini endpoint), but the source tree is clean.

### Migration from v0.2.x

If you had the backend running on an Oracle box, you can shut it down — the
APK no longer needs it. Install the new APK over v0.2.1; old settings
(backend URL / token) become unused but harmless.

### A note on the baked-in key

The key is a free-tier AI Studio key with a 1500 requests/day cap, no cost.
Public APK means the quota is shared across everyone who downloads. If you
hit the limit, rotate the `GEMINI_API_KEY` repo secret and push a new tag.

## v0.2.1 — 2026-05-10

The share-intent release.

- **Share-to-codehunt works.** When you're on a checkout page in Chrome, tap
  the share button and pick codehunt — the URL pre-fills on the home screen
  and the hunt runs automatically. Same flow whether the app is cold-launched
  by the share or already running in the background.
- **Implementation: native MainActivity + method channel.** The Kotlin side
  reads `ACTION_SEND` payloads in `onCreate` and `onNewIntent` and pushes the
  URL to Dart over a `codehunt.share` method channel. No third-party plugin
  — bypasses the JVM target / AGP namespace gradle pain that blocked
  `receive_sharing_intent` in v0.2.0. `scripts/patch_android.py` injects the
  MainActivity body after `flutter create` scaffolds it.

### Migration from v0.2.0

Nothing to do beyond installing the new APK. Backend and settings are
unchanged.

## v0.2.0 — 2026-05-10

The mobile release.

- **Android app.** Native Flutter app you sideload from the Releases page.
  Enter a URL, get a confidence-ranked list of codes back. Settings screen
  shows the installed version + DazedDingo signature.
- **Backend (`backend/`).** Thin FastAPI proxy that lives on a Linux box you
  control. The Gemini key stays on the server; the app talks to it with a
  bearer token you generate. Reuses the CLI's `hunt_gemini` / `hunt_claude`
  functions so all three surfaces behave identically. Ships with a systemd
  unit and a deploy guide.
- **APK built and attached automatically on every tagged release.** GitHub
  Actions builds `codehunt-vX.Y.Z.apk` and uploads it to the Release page —
  no manual builds.
- **Lint widened to cover `backend/` and `scripts/`** in the existing CI.

### Deferred to v0.2.1

- **Share-to-codehunt from Chrome.** I tried wiring this up via the
  `receive_sharing_intent` package but every recent version forces a Kotlin
  JVM 17 / Java 1.8 mismatch on the plugin module that Gradle 8+ refuses to
  build, and AGP finalizes `compileOptions` before any subprojects hook can
  override it. Older versions of the package (1.4.5) work but predate AGP
  8's namespace requirement. v0.2.1 will ship a native MainActivity +
  method-channel implementation — bypasses the third-party gradle problem
  entirely.

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
