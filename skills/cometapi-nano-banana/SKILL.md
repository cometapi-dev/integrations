---
name: cometapi-nano-banana
description: |
  Generate, edit, compose, and batch-generate images through CometAPI using Gemini 3 Pro Image
  in a Nano Banana-style workflow. Use this when the user wants prompt-only image generation,
  reference-guided edits, multi-image composition, or multiple creative variants from the same setup.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# CometAPI Nano Banana

## When to Use This Skill

- The user wants Gemini-based image generation with a simple focused workflow.
- The user wants to edit an image using a natural-language instruction.
- The user wants to combine multiple source images into one generated result.
- The user wants several variants from the same prompt or edit setup.

## Model

- Fixed default model: `gemini-3-pro-image-preview`
- Resolution options: `1K`, `2K`, `4K`
- Supports prompt-only generation, edit, and compose modes
- Supports up to 5 repeated `--input-image` references
- Loads an optional system template from `assets/SYSTEM_TEMPLATE`

## How to Use

```bash
python scripts/generate_image.py --prompt "A cinematic sunset over snow-capped mountains" --output sunset.png
python scripts/generate_image.py --mode edit --prompt "Replace the sky with a dramatic aurora" --input-image input.jpg --output aurora.png
python scripts/generate_image.py --mode compose --prompt "Combine these people into a single studio portrait" --input-image face1.jpg --input-image face2.jpg --output composite.png
python scripts/generate_image.py --mode compose --prompt "Create three poster variations from these references" --input-image subject.png --input-image logo.png --count 3 --parallel 2 --output-dir variants --prefix launch-poster
```

## Behavior

- Reads the CometAPI key from `COMETAPI_KEY`
- Saves one or more generated images locally
- Prints `MEDIA: <path>` for each saved image
- Writes a sidecar metadata file next to the output for traceability
- Records rendered prompt, selected mode, input references, and SHA-256 hashes for local inputs and outputs
- Supports repeated variant generation with `--count`, `--parallel`, and `--delay`

## Prompt Control

- Add `--style-note` to steer the art direction without changing the core request.
- Add `--layout-note` to enforce composition structure.
- Add `--preserve-note` when the important subject details must remain recognizable.
- Edit `assets/SYSTEM_TEMPLATE` if a project needs a stronger default visual direction.

## Operational Rules

1. Use this skill instead of ad hoc Gemini image API code when the user clearly wants a Nano Banana-style image workflow.
2. Keep outputs in the workspace unless the user asked for another destination.
3. Preserve every prompt and input reference in the generated metadata JSON.
4. For edit and compose requests, prefer explicit preservation notes instead of assuming which source details matter most.
5. Do not claim factual grounding; this skill is for image generation and editing, not research.