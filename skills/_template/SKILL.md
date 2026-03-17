---
name: _template
description: |
  Template only. Duplicate this folder into a real CometAPI skill directory,
  then replace the metadata and instructions with the actual skill content.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# Skill Title

## When to Use This Skill

- Use case 1.
- Use case 2.
- Use case 3.

## Prerequisites

- `COMETAPI_KEY` must be available in the environment.
- Any helper scripts should remain runnable after this folder is copied into another agent's skills directory.

## Instructions

1. Confirm the user task matches this skill.
2. Choose the right CometAPI model or endpoint for the request.
3. Run the helper script from this skill folder when it improves reliability or repeatability.
4. Save generated assets into the user's workspace unless they explicitly ask for another location.
5. Report the created file path or returned artifact in a concise way.

## Examples

```bash
python scripts/example.py "Describe the task here"
```

## Notes for Maintainers

- Keep the skill generic across Copilot, Claude Code, Cursor, Gemini CLI, and Codex-style hosts.
- Prefer relative file paths and standard-library helpers where practical.
- Do not hardcode secrets.