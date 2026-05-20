"""Tests for codehunt — pure functions and CLI surface only.

No network calls. Live provider behavior is tested manually against the API.
"""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from codehunt import (  # noqa: E402
    __version__,
    _parse_json_loose,
    extract_domain,
    locale_hint_for_domain,
)

SCRIPT = ROOT / "codehunt.py"


class TestExtractDomain(unittest.TestCase):
    def test_bare_domain(self):
        self.assertEqual(extract_domain("example.com"), "example.com")

    def test_strips_https(self):
        self.assertEqual(extract_domain("https://example.com"), "example.com")

    def test_strips_www(self):
        self.assertEqual(extract_domain("https://www.example.com"), "example.com")

    def test_strips_path_and_query(self):
        self.assertEqual(extract_domain("https://example.com/checkout?x=1"), "example.com")

    def test_keeps_subdomain(self):
        self.assertEqual(extract_domain("https://shop.example.co.uk/path"), "shop.example.co.uk")

    def test_lowercases(self):
        self.assertEqual(extract_domain("WWW.EXAMPLE.COM"), "example.com")


class TestLocaleHint(unittest.TestCase):
    def test_uk(self):
        self.assertIn("UK", locale_hint_for_domain("thegainsboroughbathspa.co.uk"))

    def test_uk_bare_tld(self):
        self.assertIn("UK", locale_hint_for_domain("example.uk"))

    def test_germany(self):
        self.assertIn("Germany", locale_hint_for_domain("shop.de"))

    def test_australia_compound_tld(self):
        self.assertIn("Australia", locale_hint_for_domain("shop.com.au"))

    def test_subdomain_uk(self):
        # Compound TLD inside a subdomain
        self.assertIn("UK", locale_hint_for_domain("checkout.example.co.uk"))

    def test_us_unknown(self):
        # .com is intentionally not in the table — let the model handle it.
        self.assertEqual(locale_hint_for_domain("example.com"), "")

    def test_empty(self):
        self.assertEqual(locale_hint_for_domain(""), "")

    def test_single_label(self):
        self.assertEqual(locale_hint_for_domain("localhost"), "")


class TestParseJsonLoose(unittest.TestCase):
    def test_plain_json(self):
        self.assertEqual(_parse_json_loose('{"a": 1}'), {"a": 1})

    def test_code_fenced_with_lang(self):
        self.assertEqual(_parse_json_loose('```json\n{"a": 1}\n```'), {"a": 1})

    def test_code_fenced_no_lang(self):
        self.assertEqual(_parse_json_loose('```\n{"a": 1}\n```'), {"a": 1})

    def test_prose_around_json(self):
        self.assertEqual(
            _parse_json_loose('Here is the result: {"a": 1} hope that helps'),
            {"a": 1},
        )

    def test_invalid_raises(self):
        with self.assertRaises(json.JSONDecodeError):
            _parse_json_loose("not json at all")


class TestCli(unittest.TestCase):
    def test_version_flag(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--version"],
            capture_output=True, text=True, check=True,
        )
        self.assertIn(__version__, result.stdout)

    def test_help_flag(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--help"],
            capture_output=True, text=True, check=True,
        )
        self.assertIn("--provider", result.stdout)
        self.assertIn("--json", result.stdout)

    def test_gemini_without_key_fails_cleanly(self):
        env = {k: v for k, v in os.environ.items() if k != "GEMINI_API_KEY"}
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "example.com"],
            capture_output=True, text=True, env=env,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("GEMINI_API_KEY", result.stderr)

    def test_claude_provider_fails_cleanly_without_credentials(self):
        # Either path is acceptable: anthropic not installed (CI), or key missing (dev).
        env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "example.com", "--provider", "claude"],
            capture_output=True, text=True, env=env,
        )
        self.assertEqual(result.returncode, 1)
        self.assertTrue(
            "anthropic" in result.stderr or "ANTHROPIC_API_KEY" in result.stderr,
            f"unexpected stderr: {result.stderr!r}",
        )


if __name__ == "__main__":
    unittest.main()
