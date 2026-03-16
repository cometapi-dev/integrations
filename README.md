# CometAPI Integrations

One-command setup scripts for popular AI frameworks.

## OpenClaw

Add CometAPI as a provider to your [OpenClaw](https://openclaw.ai) installation.

### macOS / Linux / WSL

```bash
# Interactive (prompts for your API key)
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.sh | sh

# Non-interactive / CI — pass key directly
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.sh | sh -s -- --key <COMETAPI_KEY>
```

### Windows (PowerShell)

```powershell
# Interactive (prompts for your API key)
irm https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.ps1 | iex

# Non-interactive / CI — pass key directly
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.ps1'))) -Key <COMETAPI_KEY>
```

> **Note:** `irm ... | iex` doesn't support passing arguments. Use the `scriptblock` form above when you need to supply `-Key` inline.

---

Get your API key at [www.cometapi.com/console/token](https://www.cometapi.com/console/token)

Integration setup scripts for CometAPI — OpenClaw and more (coming soon)!
