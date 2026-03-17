# CometAPI Integrations

One-command setup scripts and reusable skills for popular AI frameworks and AI assistants.

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
- `cometapi-nano-banana` - Gemini image generation, editing, and multi-image composition through CometAPI.
- `cometapi-infographics` - Structured infographic generation through CometAPI with traceable prompt metadata.

See [`skills/README.md`](skills/README.md) for the catalog, install paths, and usage.

## Skill Intake Pipeline

The repository now includes a strict intake workflow for discovering, cloning, validating, and scoring external skills before they are allowed into the committed CometAPI catalog.

- Runtime artifacts live under `.tmp/` and are gitignored.
- The written process is in [`skill-intake/SOP.md`](skill-intake/SOP.md).
- The automation entrypoint is [`skill-intake/scripts/pipeline.py`](skill-intake/scripts/pipeline.py).
- Only candidates that pass the promotion gate are allowed into [`skill-intake/registry/verified_candidates.json`](skill-intake/registry/verified_candidates.json).

---

Get your API key at [www.cometapi.com/console/token](https://www.cometapi.com/console/token)

Integration setup scripts and portable skills for CometAPI — OpenClaw today, more integrations on the way.
