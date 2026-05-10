#!/usr/bin/env python3
"""Patch Flutter-generated Android scaffolding for codehunt.

Applies:
  1. SEND intent filter to AndroidManifest.xml (so Chrome's share sheet sees us).
  2. JVM 17 target in app/build.gradle.kts (receive_sharing_intent compiles
     Kotlin to JVM 17; Flutter's default Java target is 11 → mismatch).

Run from app/ after `flutter create . --platforms=android`. Idempotent.
"""

import re
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


def patch_gradle() -> bool:
    gradle = Path("android/app/build.gradle.kts")
    if not gradle.exists():
        print(f"error: {gradle} not found", file=sys.stderr)
        return False
    text = gradle.read_text()

    # Java source/target compatibility → 17
    text = re.sub(
        r"sourceCompatibility\s*=\s*JavaVersion\.VERSION_\d+",
        "sourceCompatibility = JavaVersion.VERSION_17",
        text,
    )
    text = re.sub(
        r"targetCompatibility\s*=\s*JavaVersion\.VERSION_\d+",
        "targetCompatibility = JavaVersion.VERSION_17",
        text,
    )
    # Kotlin jvmTarget → 17
    text = re.sub(
        r"jvmTarget\s*=\s*JavaVersion\.VERSION_\d+\.toString\(\)",
        'jvmTarget = JavaVersion.VERSION_17.toString()',
        text,
    )
    text = re.sub(
        r'jvmTarget\s*=\s*"\d+"',
        'jvmTarget = "17"',
        text,
    )

    gradle.write_text(text)
    print("gradle: patched JVM targets to 17")
    return True


if __name__ == "__main__":
    ok = patch_manifest() and patch_gradle()
    sys.exit(0 if ok else 1)
