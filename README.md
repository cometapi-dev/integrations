# CometAPI Integrations

One-command setup scripts for popular AI frameworks.

## OpenClaw

Add CometAPI as a provider to your [OpenClaw](https://openclaw.ai) installation.

**macOS / Linux / WSL:**
```bash
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.sh | sh
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.ps1 | iex
```

**Non-interactive (CI / scripted):**
```bash
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.sh | sh -s -- --key sk-xxxxx
```

---

Get your API key at [www.cometapi.com/console/token](https://www.cometapi.com/console/token)
Integration setup scripts for CometAPI — OpenClaw, LiteLLM, and more
