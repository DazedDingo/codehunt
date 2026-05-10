#!/usr/bin/env python3
"""Patch Flutter-generated Android scaffolding for codehunt.

Applies:
  1. SEND intent filter to AndroidManifest.xml (so Chrome's share sheet sees us).
  2. JVM 17 enforcement on every subproject (app + every plugin module).
     receive_sharing_intent compiles its own Kotlin to JVM 17, but the Java
     compile task on plugin modules falls back to JVM 1.8 by default — Gradle
     hard-fails the release build on this mismatch. The subprojects block
     below forces every Android module to compile both Java and Kotlin to 17.

Run from app/ after `flutter create . --platforms=android`. Idempotent.
"""

import sys
from pathlib import Path

# Compatible with both old kotlinOptions DSL and current Android Gradle Plugin.
SUBPROJECTS_PATCH = """

subprojects {
    afterEvaluate {
        plugins.withId("com.android.application") {
            extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}
"""

PATCH_MARKER = "// codehunt: JVM 17 subprojects patch"


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


def patch_root_gradle() -> bool:
    gradle = Path("android/build.gradle.kts")
    if not gradle.exists():
        print(f"error: {gradle} not found", file=sys.stderr)
        return False
    text = gradle.read_text()
    if PATCH_MARKER in text:
        print("root gradle: already patched")
        return True
    gradle.write_text(text + "\n" + PATCH_MARKER + SUBPROJECTS_PATCH)
    print("root gradle: appended JVM 17 subprojects block")
    return True


if __name__ == "__main__":
    ok = patch_manifest() and patch_root_gradle()
    sys.exit(0 if ok else 1)
