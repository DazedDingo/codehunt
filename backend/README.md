# codehunt backend

A thin FastAPI proxy that lets the Android app call Gemini (or Claude) without
shipping API keys to user devices. Reuses the CLI's `hunt_gemini` /
`hunt_claude` functions so behavior stays identical across the two surfaces.

## Endpoints

| Method | Path        | Auth             | Purpose                                    |
| ------ | ----------- | ---------------- | ------------------------------------------ |
| `GET`  | `/healthz`  | none             | Liveness check; returns version.           |
| `POST` | `/hunt`     | bearer token     | Run a hunt. Body: `{target, provider}`.    |

The bearer token is whatever you set in `CODEHUNT_API_TOKEN` — the app sends
`Authorization: Bearer <that>` on every request.

## Deploy on a Linux box

```bash
# 1. Clone repo as the codehunt user
sudo useradd -r -m -d /opt/codehunt codehunt
sudo -u codehunt git clone https://github.com/DazedDingo/codehunt.git /opt/codehunt
cd /opt/codehunt

# 2. Install dependencies into a venv
sudo -u codehunt python3 -m venv .venv
sudo -u codehunt .venv/bin/pip install -r requirements.txt -r backend/requirements.txt

# 3. Generate a random token and write the env file
TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
sudo -u codehunt tee /opt/codehunt/.env >/dev/null <<EOF
GEMINI_API_KEY=AIza...
CODEHUNT_API_TOKEN=$TOKEN
EOF
sudo chmod 600 /opt/codehunt/.env

# 4. Install + start the systemd unit
sudo cp backend/codehunt.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now codehunt
sudo systemctl status codehunt

# 5. Smoke test
curl http://127.0.0.1:8080/healthz
```

The service binds to `127.0.0.1:8080` by default. Front it with nginx + Let's
Encrypt for TLS, or expose via Cloudflare Tunnel — the app needs HTTPS.

## Local development

```bash
cd /path/to/codehunt
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -r backend/requirements.txt
GEMINI_API_KEY=... CODEHUNT_API_TOKEN=dev .venv/bin/uvicorn backend.server:app --reload
```

Then in the Android app's Settings, point base URL at `http://10.0.2.2:8080`
(emulator) or `http://<your-laptop-ip>:8080` (physical device on same network)
and use `dev` as the token.
