# CometAPI Integrations

One-command setup scripts for popular AI frameworks.

## OpenClaw

Add CometAPI as a provider to your [OpenClaw](https://openclaw.ai) installation.

### macOS / Linux / WSL

```bash
# Install / update providers
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.sh | sh -s -- --key <COMETAPI_KEY>

# Add a model on first run or in CI
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.sh | sh -s -- --key <COMETAPI_KEY> --add-model cometapi-openai/gpt-5.2-chat-latest

# Add a model later (reuses ~/.openclaw/.env if COMETAPI_KEY was already saved)
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.sh | sh -s -- --add-model cometapi-openai/gpt-5.2-chat-latest
```

### Windows (PowerShell)

```powershell
# Install / update providers
powershell -c "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.ps1'))) -Key '<COMETAPI_KEY>'"

# Interactive alternative (prompts for your API key)
powershell -c "irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.ps1' | iex"

# Add a model on first run or in CI
powershell -c "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.ps1'))) -Key '<COMETAPI_KEY>' -AddModel 'cometapi-openai/gpt-5.2-chat-latest'"

# Add a model later (reuses ~/.openclaw/.env if COMETAPI_KEY was already saved)
powershell -c "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/openclaw/setup.ps1'))) -AddModel 'cometapi-openai/gpt-5.2-chat-latest'"
```

> `powershell -c "irm ... | iex"` is the widest copy-paste form on Windows, similar to Bun's installer.
> `irm ... | iex` only works once you're already inside a PowerShell session, and it can't accept `-Key` or `-AddModel` arguments.

---

Get your API key at [www.cometapi.com/console/token](https://www.cometapi.com/console/token)

Integration setup scripts for CometAPI — OpenClaw and more (coming soon)!
