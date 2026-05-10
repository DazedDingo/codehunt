#!/usr/bin/env python3
"""codehunt: ask an LLM to find working coupon codes for a URL or domain.

Defaults to Gemini 2.5 Flash with Google Search grounding (free tier, ~1500 req/day).
Pass --provider claude to use Claude Sonnet 4.6 with web_search instead (paid).
"""

import argparse
import json
import os
import sys
from urllib.parse import urlparse

__version__ = "0.6.0"

# JSON schema used by the Claude path (structured outputs) and described in the
# Gemini prompt (which can't combine grounding with response_schema reliably).
SCHEMA = {
    "type": "object",
    "properties": {
        "codes": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "code": {
                        "type": "string",
                        "description": "The coupon code as the customer would type it at checkout.",
                    },
                    "discount": {
                        "type": "string",
                        "description": "What the code does (e.g. '10% off', 'free shipping over $50').",
                    },
                    "confidence": {
                        "type": "string",
                        "enum": ["high", "medium", "low"],
                        "description": (
                            "high: multiple recent sources confirm or the merchant posted it directly. "
                            "medium: a reputable aggregator with recent positive feedback. "
                            "low: stale, unverified, or you're not sure."
                        ),
                    },
                    "source": {
                        "type": "string",
                        "description": (
                            "URL to the page where you saw the code, fully qualified "
                            "(starting with https://). If you genuinely can't get a "
                            "URL, fall back to the site name."
                        ),
                    },
                    "notes": {
                        "type": "string",
                        "description": "Restrictions, expiry hints, or caveats. Empty string if none.",
                    },
                },
                "required": ["code", "discount", "confidence", "source", "notes"],
                "additionalProperties": False,
            },
        },
        "summary": {
            "type": "string",
            "description": "One-line summary of what was found, or why nothing was found.",
        },
    },
    "required": ["codes", "summary"],
    "additionalProperties": False,
}

PROMPT_TEMPLATE = """Find currently-working coupon, promo, or discount codes for this domain: {domain}

Search across multiple sources — RetailMeNot, Honey, Slickdeals, Reddit threads, \
the merchant's own social media, recent forum posts. Look for codes that are recent \
and have positive feedback from real users.

For each code, assess confidence it actually works *right now*:
- high: multiple recent sources confirm, or the merchant posted it directly.
- medium: listed on a reputable aggregator with recent positive user feedback.
- low: older, unverified, or you suspect it may have expired.

Important rules:
- Do NOT invent plausible-looking codes. Only return codes you actually observed on a source.
- Discard any code whose only sources are low-quality aggregator catalogs like \
**Coupert, PromoPro, CouponBirds, CouponXoo, or DontPayFull** — these sites \
generate plausible-looking codes that rarely work. Only include a code from these sources \
if a separate reputable source (RetailMeNot, Honey, Slickdeals, Reddit, the merchant's own \
social media) independently confirms it.
- If no real codes exist, return an empty list and explain in the summary. Many boutique \
merchants genuinely don't run public promos — an honest "none found" is the right answer.
- Don't include codes that are clearly account-gated, region-locked, or first-purchase-only \
unless you flag the restriction in notes.
- For the source field, return a fully-qualified URL (https://...) whenever you can.
"""

JSON_INSTRUCTION = """Return your answer as a single JSON object with this exact shape:

{
  "summary": "<one-line summary>",
  "codes": [
    {
      "code": "<the code>",
      "discount": "<what it does>",
      "confidence": "high" | "medium" | "low",
      "source": "<where you saw it>",
      "notes": "<restrictions or empty string>"
    }
  ]
}

Output ONLY the JSON object — no prose before or after, no code fences."""

CONFIDENCE_RANK = {"high": 0, "medium": 1, "low": 2}


def extract_domain(target: str) -> str:
    """Strip a URL or bare domain down to its registrable host."""
    if "://" not in target:
        target = "https://" + target
    parsed = urlparse(target)
    host = (parsed.netloc or parsed.path).lower().strip("/")
    if host.startswith("www."):
        host = host[4:]
    return host


def _parse_json_loose(text: str) -> dict:
    """Parse JSON that may be wrapped in code fences or have leading/trailing prose."""
    text = text.strip()
    if text.startswith("```"):
        first_nl = text.find("\n")
        if first_nl != -1:
            text = text[first_nl + 1:]
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()
    # Last-resort: find the outermost {...}
    if not text.startswith("{"):
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            text = text[start:end + 1]
    return json.loads(text)


def hunt_gemini(domain: str) -> dict:
    try:
        from google import genai
        from google.genai import types
    except ImportError:
        raise RuntimeError("google-genai not installed; run: pip install google-genai")

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set")

    client = genai.Client(api_key=api_key)
    prompt = PROMPT_TEMPLATE.format(domain=domain) + "\n\n" + JSON_INSTRUCTION

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt,
        config=types.GenerateContentConfig(
            tools=[types.Tool(google_search=types.GoogleSearch())],
        ),
    )
    if not response.text:
        raise RuntimeError("Empty response from Gemini")
    return _parse_json_loose(response.text)


def hunt_claude(domain: str) -> dict:
    try:
        import anthropic
    except ImportError:
        raise RuntimeError("anthropic not installed; run: pip install anthropic")

    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise RuntimeError("ANTHROPIC_API_KEY is not set")

    client = anthropic.Anthropic()
    with client.messages.stream(
        model="claude-sonnet-4-6",
        max_tokens=16000,
        thinking={"type": "adaptive"},
        output_config={
            "format": {"type": "json_schema", "schema": SCHEMA},
            "effort": "high",
        },
        tools=[{"type": "web_search_20260209", "name": "web_search"}],
        messages=[{"role": "user", "content": PROMPT_TEMPLATE.format(domain=domain)}],
    ) as stream:
        message = stream.get_final_message()

    if message.stop_reason == "pause_turn":
        raise RuntimeError(
            "Model paused mid-search (server tool iteration limit). Re-run the command."
        )
    if message.stop_reason == "refusal":
        raise RuntimeError("Model refused the request.")

    text = next((b.text for b in message.content if b.type == "text"), None)
    if text is None:
        raise RuntimeError(f"No text block in response. stop_reason={message.stop_reason}")
    return json.loads(text)


PROVIDERS = {
    "gemini": hunt_gemini,
    "claude": hunt_claude,
}


def render_human(domain: str, provider: str, result: dict) -> None:
    codes = sorted(
        result.get("codes", []),
        key=lambda c: CONFIDENCE_RANK.get(c.get("confidence", ""), 99),
    )
    print(f"codehunt v{__version__}")
    print(f"Domain:   {domain}")
    print(f"Provider: {provider}")
    print(f"Summary:  {result.get('summary', '')}")
    print()

    if not codes:
        print("No codes found.")
        return

    for c in codes:
        print(f"  [{c['confidence']:>6}]  {c['code']}")
        print(f"           {c['discount']}")
        print(f"           source: {c['source']}")
        if c.get("notes"):
            print(f"           note:   {c['notes']}")
        print()


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="codehunt",
        description="Find currently-working coupon codes for a URL or domain.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    parser.add_argument("target", help="URL or domain, e.g. example.com or https://example.com/checkout")
    parser.add_argument(
        "--provider",
        choices=list(PROVIDERS),
        default="gemini",
        help="LLM provider (default: gemini, free-tier Flash with Google Search grounding)",
    )
    parser.add_argument("--json", action="store_true", help="Print raw JSON instead of formatted output")
    args = parser.parse_args()

    domain = extract_domain(args.target)
    if not domain:
        print(f"error: could not extract a domain from {args.target!r}", file=sys.stderr)
        return 2

    try:
        result = PROVIDERS[args.provider](domain)
    except (RuntimeError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"error: {type(e).__name__}: {e}", file=sys.stderr)
        return 1

    if args.json:
        json.dump(result, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        render_human(domain, args.provider, result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
