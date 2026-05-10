# Changelog

All notable changes to codehunt are documented here. Each release entry is
written as plain-English bullets — what changed and why it matters — not raw
commit subjects.

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
