# Batch 2-3 Manual Triage

Second-pass review of the `manual_review` candidates from:

- `offset-0025-top-0025`
- `offset-0050-top-0025`

This document is intentionally stricter than the automated gate. The goal is to identify only the next conversions that look strong enough to become committed CometAPI skills.

## Shortlist

### `agent-designer`

- Source repo: `alirezarezvani/claude-skills`
- Source path: `engineering/agent-designer/SKILL.md`
- Verdict: `shortlist`
- Why it survived:
  - Strong direct fit for CometAPI users building multi-agent systems on top of model APIs.
  - The skill body covers concrete architecture patterns, role definitions, orchestration, guardrails, evaluation, and memory.
  - The upstream package includes helper code that can be repurposed into CometAPI-oriented agent-planning utilities.
- Conversion direction:
  - Convert into a CometAPI multi-agent architecture skill focused on model/provider selection, orchestration patterns, and tool schema design.

### `mcp-builder`

- Source repo: `microsoft/skills`
- Source path: `.github/skills/mcp-builder/SKILL.md`
- Verdict: `shortlist`
- Why it survived:
  - Better than the duplicate generic `mcp-builder` variants because it adds Microsoft/Azure MCP ecosystem guidance and transport decisions.
  - Valuable to CometAPI users who need to build model-facing tools and remote server integrations.
  - The skill is reference-heavy, which makes it suitable for a curated CometAPI conversion rather than a direct copy.
- Conversion direction:
  - Convert into a CometAPI MCP integration skill focused on building MCP servers that call CometAPI-backed models and toolchains.

### `cortex-mine`

- Source repo: `jezweb/claude-skills`
- Source path: `plugins/knowledge-cortex/skills/cortex-mine/SKILL.md`
- Verdict: `shortlist`
- Why it survived:
  - It is a concrete end-user workflow rather than a generic writing or coding guide.
  - Uses model extraction over Gmail history and stores structured local knowledge, which can be re-routed to CometAPI's Anthropic-compatible path.
  - The workflow is narrow but real, and it demonstrates a serious automation pattern instead of shallow prompt advice.
- Conversion direction:
  - Convert into an optional CometAPI personal-knowledge mining skill only if the repo wants workflow-oriented integrations beyond pure generation skills.

## Hold

### `skill-creator`

- Source repo: `feiskyer/claude-code-settings`
- Source path: `skills/skill-creator/SKILL.md`
- Verdict: `hold`
- Why it is not shortlisted yet:
  - The high-level concept is useful, but the upstream tooling runs evaluation loops and dynamic adapters that deserve a dedicated security pass before any conversion.
  - This is a meta-skill for creating more skills, so the bar for safety and reproducibility should be higher than a normal content-generation workflow.
- Required before conversion:
  - Manual security review of the upstream evaluation scripts.

## Reject

### `tdd-guide` (both copies)

- Source repos:
  - `alirezarezvani/claude-skills`
  - `alirezarezvani/claude-code-skill-factory`
- Verdict: `reject`
- Why rejected:
  - This is an engineering-practice skill, not a model-gateway or CometAPI-specific integration.
  - The value is largely local testing workflow guidance, with references to Playwright/Cypress/Selenium and similar local tooling.
  - It does not create a strong product fit for the CometAPI integrations catalog.

### Generic `mcp-builder` duplicates

- Source repos:
  - `ThinkInAIXYZ/deepchat`
  - `davepoon/buildwithclaude`
  - `Prat011/awesome-llm-skills`
- Verdict: `reject`
- Why rejected:
  - These are duplicate generic variants of `mcp-builder`.
  - The Microsoft variant has a clearer differentiator and is the only one worth considering for conversion.

## Recommended Next Conversions

Priority order for the next committed conversions:

1. `agent-designer`
2. `mcp-builder` from `microsoft/skills`
3. `cortex-mine` if workflow-oriented skills remain in scope

## Notes

- This review is not a promotion into `verified_candidates.json`.
- It is a human shortlist for the next conversion wave.
- The supporting batch evidence remains under `.tmp/skill-intake/batches/`.