# CometAPI Skills

Portable `SKILL.md` packages for AI assistants that need a clean, reusable way to call CometAPI.

These skills are designed to stay generic instead of coupling themselves to a single host like OpenClaw. Each skill keeps its helper scripts alongside `SKILL.md` so the same folder can be copied into different agent ecosystems.

## Goals

- Work across GitHub Copilot, Claude Code, Cursor, Gemini CLI, Codex/OpenCode, and similar tools.
- Hide provider-specific API quirks behind CometAPI.
- Keep authentication consistent with `COMETAPI_KEY`.
- Prefer self-contained helper scripts that can run after the skill folder is copied elsewhere.

## Layout

```text
skills/
├── README.md
├── _template/
│   └── SKILL.md
├── cometapi-image-gen/
│   ├── SKILL.md
│   └── scripts/
│       └── generate_image.py
├── cometapi-infographics/
│   ├── SKILL.md
│   └── scripts/
│       └── generate_infographic.py
└── cometapi-nano-banana/
    ├── SKILL.md
    └── scripts/
        └── generate_image.py
```

Planned next skills:

- `cometapi-video-gen`
- `cometapi-music-gen`
- `cometapi-tts`
- `cometapi-image-edit`
- `cometapi-multimodal`

## Install Paths

Copy a skill folder into the location your assistant watches for `SKILL.md` packages.

| Tool | Workspace path | Global path |
| --- | --- | --- |
| GitHub Copilot | `.github/skills/` | `~/.copilot/skills/` |
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| Cursor | `.cursor/skills/` | `~/.cursor/skills/` |
| Gemini CLI | `.gemini/skills/` | `~/.gemini/skills/` |
| Codex / OpenCode | `.agents/skills/` | `~/.agents/skills/` |
| Antigravity | `.agent/skills/` | `~/.gemini/antigravity/skills/` |

Example:

```bash
mkdir -p .github/skills
cp -R cometapi-dev/integrations/skills/cometapi-image-gen .github/skills/
```

## Available Skills

### `cometapi-image-gen`

Image generation through CometAPI with one agent-facing workflow covering:

- `gemini-3-pro-image-preview`
- `gpt-image-1.5`
- `dall-e-3`
- `flux-2-pro`

The helper script uses Python's standard library only, so the copied skill does not need extra packages before it can run.

### `cometapi-nano-banana`

Specialized Gemini image generation, editing, and multi-image composition through CometAPI.

- Based on the popular Nano Banana workflow pattern
- Defaults to `gemini-3-pro-image-preview`
- Accepts repeated input images for edits and composites
- Writes a sidecar metadata JSON file for traceability

### `cometapi-infographics`

Specialized infographic generation through CometAPI with structured prompt building.

- Converts the popular infographic skill pattern into a CometAPI-native workflow
- Supports infographic type, style, palette, and document-type presets
- Can ground the output with `--fact` or `--facts-file`
- Writes the fully rendered prompt and inputs to a sidecar metadata JSON file

## Authoring Rules

- Keep host-specific instructions out of the skill body unless absolutely necessary.
- Put helper scripts under `scripts/` with relative paths only.
- Read credentials from `COMETAPI_KEY`.
- Prefer one generic CometAPI workflow over provider-specific prompts unless the provider behavior is materially different.
- Keep `SKILL.md` small and load heavy resources on demand.

## Template

Start from [`_template/SKILL.md`](_template/SKILL.md) when adding the next CometAPI skill.