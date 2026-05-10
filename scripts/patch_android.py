#!/usr/bin/env python3
"""Patch Flutter-generated Android scaffolding for codehunt.

Currently injects only the SEND intent filter into AndroidManifest.xml so that
Chrome's share sheet shows codehunt as a target. Run from the app/ directory
after `flutter create . --platforms=android`. Idempotent.
"""

import sys
from pathlib import Path


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


if __name__ == "__main__":
    sys.exit(0 if patch_manifest() else 1)
