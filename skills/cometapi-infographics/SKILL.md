---
name: cometapi-infographics
description: |
  Create infographic-style images through CometAPI using a structured prompt builder.
  Use this when the user wants data storytelling, timelines, comparisons, process diagrams,
  social infographics, or presentation visuals and the output should stay traceable.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# CometAPI Infographics

## When to Use This Skill

- The user wants an infographic instead of a generic illustration.
- The request has a clear structure such as timeline, comparison, list, process, or statistical summary.
- The output should preserve the exact facts or notes used to build the image.

## Model

- Default image model: `gemini-3-pro-image-preview`
- Default output shape favors infographic layouts, but the aspect ratio can be changed.

## Grounding Rules

- If the user supplies exact facts, pass them through `--fact` or `--facts-file`.
- If facts are supplied, the generated prompt explicitly instructs the model not to invent additional statistics.
- If facts are not supplied, use qualitative wording and avoid pretending the result is source-grounded.

## How to Use

```bash
python scripts/generate_infographic.py "5 benefits of regular exercise" --type list --output exercise.png
python scripts/generate_infographic.py "Global AI market growth" --type statistical --style technology --fact "2025 market size: $391 billion" --fact "Projected CAGR: 35.9%" --output ai-market.png
python scripts/generate_infographic.py "History of machine learning breakthroughs" --type timeline --style education --facts-file notes/ml_timeline.txt --output ml-timeline.png
```

## Traceability

- The helper always writes a sidecar metadata JSON file.
- The metadata includes the rendered prompt, facts, presets, and generated output path.

## Operational Rules

1. Prefer this skill over generic image generation when the output is explicitly an infographic or data story.
2. Keep the user's factual inputs visible in the metadata file.
3. Do not claim research or citation validation unless the user supplied source-grounded inputs.
4. If the request is really a scientific diagram rather than an infographic, route it to a schematic or diagram workflow instead of forcing this skill.