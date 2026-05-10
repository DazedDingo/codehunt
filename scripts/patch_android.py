#!/usr/bin/env python3
"""Patch Flutter-generated Android scaffolding for codehunt.

Applies, idempotently:
  1. INTERNET permission on the main AndroidManifest.xml. Without this, release
     APKs throw "no address associated with hostname" on every network call —
     `flutter create` only adds the permission to the *debug* manifest.
  2. SEND intent filter on AndroidManifest.xml so Chrome's share sheet offers
     codehunt as a target for shared URLs.
  3. MainActivity.kt — replaces the bare class with one that reads
     ACTION_SEND payloads (cold launch + hot share) and forwards the URL to
     Dart over a `codehunt.share` method channel.
  4. Release signing config in app/build.gradle.kts that reads from a
     properties file at android/key.properties. The CI workflow writes that
     file from secrets; locally it's gitignored. Without this, every CI build
     debug-signs with a fresh key and existing installs refuse to update.

Run from the app/ directory after `flutter create . --platforms=android`.
"""

import re
import sys
from pathlib import Path

MAIN_ACTIVITY_TEMPLATE = """%PACKAGE%

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "codehunt.share"
    private var sharedText: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
        sharedText?.let {
            channel?.invokeMethod("shareReceived", it)
            sharedText = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(sharedText)
                    sharedText = null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        }
    }
}
"""

SIGNING_BLOCK_KTS = """
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = java.util.Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}
"""

SIGNING_CONFIG_INJECT_KTS = """    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it.toString()) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

"""

SIGNING_BLOCK_GROOVY = """
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
"""

SIGNING_CONFIG_INJECT_GROOVY = """    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

"""


def patch_manifest() -> bool:
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if not manifest.exists():
        print(f"error: {manifest} not found; did you run `flutter create`?", file=sys.stderr)
        return False
    text = manifest.read_text()
    changed = False

    if "android.permission.INTERNET" not in text:
        # Inject the uses-permission element immediately after the opening
        # <manifest> tag so it sits at the manifest root, not inside <application>.
        new_text = re.sub(
            r"(<manifest[^>]*>)",
            r"\1\n    <uses-permission android:name=\"android.permission.INTERNET\" />",
            text,
            count=1,
        )
        if new_text == text:
            print("error: could not find <manifest> opening tag", file=sys.stderr)
            return False
        text = new_text
        changed = True
        print("manifest: added INTERNET permission")
    else:
        print("manifest: INTERNET permission already present")

    if "android.intent.action.SEND" not in text:
        inject = """            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
"""
        new_text = text.replace("        </activity>", inject + "        </activity>", 1)
        if new_text == text:
            print("error: could not find </activity> in manifest", file=sys.stderr)
            return False
        text = new_text
        changed = True
        print("manifest: added SEND intent filter")
    else:
        print("manifest: SEND filter already present")

    if changed:
        manifest.write_text(text)
    return True


def patch_main_activity() -> bool:
    candidates = list(Path("android/app/src/main/kotlin").rglob("MainActivity.kt"))
    if not candidates:
        print("error: MainActivity.kt not found under android/app/src/main/kotlin", file=sys.stderr)
        return False
    activity = candidates[0]
    text = activity.read_text()

    if "codehunt.share" in text:
        print(f"MainActivity: share handling already present at {activity} — skipping")
        return True

    package_line = next((line for line in text.splitlines() if line.startswith("package ")), None)
    if not package_line:
        print(f"error: no package line in {activity}", file=sys.stderr)
        return False

    activity.write_text(MAIN_ACTIVITY_TEMPLATE.replace("%PACKAGE%", package_line))
    print(f"MainActivity: patched share handling at {activity}")
    return True


def patch_signing_config() -> bool:
    """Wire the app gradle file to read signing config from android/key.properties.

    Handles both Kotlin DSL (`build.gradle.kts`, Flutter 3.27+) and the older
    Groovy DSL (`build.gradle`, Flutter ≤3.26). Detects which one exists.
    """
    kts = Path("android/app/build.gradle.kts")
    groovy = Path("android/app/build.gradle")
    if kts.exists():
        return _patch_kts(kts)
    if groovy.exists():
        return _patch_groovy(groovy)
    print("error: neither build.gradle.kts nor build.gradle found in android/app/", file=sys.stderr)
    return False


def _patch_kts(gradle: Path) -> bool:
    text = gradle.read_text()
    if 'keystoreProperties["keyAlias"]' in text:
        print("gradle (kts): signing config already wired — skipping")
        return True
    text = text.replace("plugins {", SIGNING_BLOCK_KTS + "plugins {", 1)
    new_text = re.sub(r"android \{\n", "android {\n" + SIGNING_CONFIG_INJECT_KTS, text, count=1)
    if new_text == text:
        print("error: could not find 'android {' block in build.gradle.kts", file=sys.stderr)
        return False
    text = new_text.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
        1,
    )
    gradle.write_text(text)
    print(f"gradle (kts): wired release signing config at {gradle}")
    return True


def _patch_groovy(gradle: Path) -> bool:
    text = gradle.read_text()
    if "keystoreProperties['keyAlias']" in text:
        print("gradle (groovy): signing config already wired — skipping")
        return True
    # Insert keystore loader before `android {`, not before `plugins {` — Flutter's
    # Groovy template uses `apply plugin: ...` not `plugins { ... }`.
    text = re.sub(r"(?=^android \{)", SIGNING_BLOCK_GROOVY + "\n", text, count=1, flags=re.MULTILINE)
    new_text = re.sub(r"android \{\n", "android {\n" + SIGNING_CONFIG_INJECT_GROOVY, text, count=1)
    if new_text == text:
        print("error: could not find 'android {' block in build.gradle", file=sys.stderr)
        return False
    text = new_text.replace(
        "signingConfig signingConfigs.debug",
        "signingConfig signingConfigs.release",
        1,
    )
    gradle.write_text(text)
    print(f"gradle (groovy): wired release signing config at {gradle}")
    return True


if __name__ == "__main__":
    ok = patch_manifest() and patch_main_activity() and patch_signing_config()
    sys.exit(0 if ok else 1)
