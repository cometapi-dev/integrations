# CometAPI Skills

Portable `SKILL.md` packages for AI assistants that need a clean, reusable way to call CometAPI.

These skills follow the [Anthropic skill-creator best practices](https://github.com/anthropics/skills/tree/main/skills/skill-creator): pushy descriptions for reliable triggering, progressive disclosure to keep context lean, explain-why writing style over rigid MUSTs, and bundled helper scripts so every invocation doesn't reinvent the wheel.

## Design Principles

- **Trigger reliably.** Descriptions are deliberately "pushy" — they list specific user phrases, adjacent domains, and scenarios to combat the tendency of AI agents to undertrigger skills.
- **Explain why, not just what.** Instructions explain the reasoning behind each step so the agent can generalize to novel situations rather than follow rigid rules.
- **Progressive disclosure.** SKILL.md stays under 500 lines. Heavy resources go into `references/` and load on demand.
- **Portable across hosts.** Works in GitHub Copilot, Claude Code, Cursor, Gemini CLI, Codex/OpenCode, and similar tools.
- **Self-contained helpers.** Scripts use only the Python standard library and read credentials from `COMETAPI_KEY`.

## Skill Anatomy

```text
skill-name/
├── SKILL.md          (required — agent instructions + YAML frontmatter)
├── scripts/          (executable helpers for deterministic tasks)
├── assets/           (templates, system prompts, icons)
├── references/       (docs loaded into context on demand)
└── evals/            (test cases — evals.json)
```

## Available Skills

| Skill | What it does | Model |
|-------|-------------|-------|
| **`cometapi-image-gen`** | Multi-model image generation (Gemini, GPT Image, DALL-E, Flux) | User's choice |
| **`cometapi-nano-banana`** | Gemini image gen/edit/compose — Pro for quality, Flash for speed | `gemini-3-pro-image-preview` / `gemini-3.1-flash-image-preview` |
| **`cometapi-infographics`** | Structured infographic generation with fact grounding | `gemini-3-pro-image-preview` |
| **`cometapi-agent-designer`** | Multi-agent architecture planning with Mermaid diagrams | `gpt-4.1-mini` |

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

## Authoring Guide

Key rules for writing a new skill:

1. **Description** — Put all "when to use" info in the YAML `description`. Make it pushy — include user phrases, adjacent domains, and scenarios that should trigger the skill.
2. **Body** — Explain how things work and why. Keep under 500 lines. Use imperative form.
3. **Examples** — Include 2–3 realistic usage examples with expected output behavior.
4. **Scripts** — Bundle deterministic work in `scripts/`. Standard library only where practical.
5. **Constraints** — Explain limitations honestly with pointers to better-fit skills.