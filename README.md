# CometAPI Integrations

One-command setup scripts and reusable skills for popular AI frameworks and AI assistants.

## Codex

Add CometAPI as a provider to your local Codex app or CLI configuration.

### macOS / Linux / WSL

```bash
# Interactive install / update
sh -c "$(curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh)"

# Non-interactive install / update
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh | sh -s -- --key <COMETAPI_KEY>

# Choose a model explicitly
curl -fsSL https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.sh | sh -s -- --key <COMETAPI_KEY> --model your-model-id
```

### Windows (PowerShell)

```powershell
# Interactive install / update
powershell -c "irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.ps1' | iex"

# Non-interactive install / update
powershell -c "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.ps1'))) -Key '<COMETAPI_KEY>'"

# Choose a model explicitly
powershell -c "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/cometapi-dev/integrations/main/codex/setup.ps1'))) -Key '<COMETAPI_KEY>' -Model 'your-model-id'"
```

The default Codex setup stores the CometAPI key in `~/.codex/cometapi_api_key`
and does not replace an existing ChatGPT login in `~/.codex/auth.json`.
On Windows native PowerShell, `~/.codex` is `%USERPROFILE%\.codex`
(`$HOME\.codex` in PowerShell), typically `C:\Users\<user>\.codex`.
In WSL, it is the Linux distribution's `~/.codex`.
If interactive setup detects an existing ChatGPT `auth.json`, it asks before
replacing it with CometAPI API-key auth. Use `--force-auth-json` or
`-ForceAuthJson` only when you want Codex's legacy API-key login file to be
managed by the setup script.

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

## Skills

Reusable `SKILL.md` packages that teach GitHub Copilot, Claude Code, Cursor, Gemini CLI, Codex/OpenCode, and similar tools how to call CometAPI.

Current skills:

- `cometapi-image-gen` - Generate images through CometAPI with Gemini, GPT Image, DALL-E, and Flux models.
- `cometapi-nano-banana` - Gemini image generation, editing, and multi-image composition through CometAPI (Pro for quality, Flash for speed).
- `cometapi-infographics` - Structured infographic generation through CometAPI with traceable prompt metadata.
- `cometapi-agent-designer` - Generate multi-agent architecture briefs and Mermaid diagrams through CometAPI.

See [`skills/README.md`](skills/README.md) for the catalog, install paths, and usage.

---

Get your API key at [www.cometapi.com/console/token](https://www.cometapi.com/console/token)

Integration setup scripts and portable skills for CometAPI — OpenClaw today, more integrations on the way.
