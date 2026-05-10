#!/usr/bin/env python3
"""Inject SEND intent filter into Flutter's generated AndroidManifest.xml.

Run from the app/ directory after `flutter create . --platforms=android`.
"""

import sys
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    print(f"error: {manifest} not found; did you run `flutter create`?", file=sys.stderr)
    sys.exit(1)

text = manifest.read_text()

if "android.intent.action.SEND" in text:
    print("AndroidManifest.xml already has SEND filter; skipping.")
    sys.exit(0)

inject = """            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
"""

new_text = text.replace("        </activity>", inject + "        </activity>", 1)
if new_text == text:
    print("error: could not find </activity> in manifest", file=sys.stderr)
    sys.exit(1)

manifest.write_text(new_text)
print("Patched AndroidManifest.xml with SEND intent filter.")
