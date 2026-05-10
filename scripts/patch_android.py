#!/usr/bin/env python3
"""Patch Flutter-generated Android scaffolding for codehunt.

Applies, idempotently:
  1. SEND intent filter to AndroidManifest.xml — so Chrome's share sheet
     offers codehunt as a target for shared URLs.
  2. MainActivity.kt — replaces the bare `class MainActivity: FlutterActivity()`
     with one that reads ACTION_SEND payloads (cold launch + hot share) and
     forwards them to Dart over a `codehunt.share` method channel.

Run from the app/ directory after `flutter create . --platforms=android`.
"""

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


def patch_manifest() -> bool:
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if not manifest.exists():
        print(f"error: {manifest} not found; did you run `flutter create`?", file=sys.stderr)
        return False
    text = manifest.read_text()
    if "android.intent.action.SEND" in text:
        print("manifest: SEND filter already present — skipping")
        return True
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
    manifest.write_text(new_text)
    print("manifest: patched with SEND filter")
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


if __name__ == "__main__":
    ok = patch_manifest() and patch_main_activity()
    sys.exit(0 if ok else 1)
