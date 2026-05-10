"""codehunt backend — proxies hunt requests so the Android app doesn't ship API keys."""

import logging
import os
import sys
from pathlib import Path

# Reuse the CLI module that lives at the repo root.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from codehunt import (  # noqa: E402
    __version__,
    extract_domain,
    hunt_claude,
    hunt_gemini,
)

from fastapi import Depends, FastAPI, Header, HTTPException  # noqa: E402
from pydantic import BaseModel  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("codehunt")

app = FastAPI(title="codehunt", version=__version__)


def _check_token(authorization: str | None = Header(None)) -> None:
    expected = os.environ.get("CODEHUNT_API_TOKEN")
    if not expected:
        raise HTTPException(500, "Server misconfigured: CODEHUNT_API_TOKEN not set")
    if authorization != f"Bearer {expected}":
        raise HTTPException(401, "Unauthorized")


class Query(BaseModel):
    target: str
    provider: str = "gemini"


class Code(BaseModel):
    code: str
    discount: str
    confidence: str
    source: str
    notes: str = ""


class Result(BaseModel):
    domain: str
    provider: str
    summary: str
    codes: list[Code]


@app.get("/healthz")
def healthz() -> dict:
    return {"ok": True, "version": __version__}


@app.post("/hunt", response_model=Result, dependencies=[Depends(_check_token)])
def hunt(query: Query) -> Result:
    domain = extract_domain(query.target)
    if not domain:
        raise HTTPException(400, f"Could not extract a domain from {query.target!r}")

    log.info("hunt domain=%s provider=%s", domain, query.provider)

    if query.provider == "gemini":
        result = hunt_gemini(domain)
    elif query.provider == "claude":
        result = hunt_claude(domain)
    else:
        raise HTTPException(400, f"Unknown provider: {query.provider!r}")

    return Result(
        domain=domain,
        provider=query.provider,
        summary=result.get("summary", ""),
        codes=[Code(**c) for c in result.get("codes", [])],
    )
