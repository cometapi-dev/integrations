---
name: cometapi-image-gen
description: |
  Generate images through CometAPI using Gemini, GPT Image, DALL-E, or Flux models.
  Use this skill when the user asks for illustrations, concept art, icons, hero images,
  posters, product renders, visual mockups, or multi-reference image composition.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# CometAPI Image Generation

## When to Use This Skill

- The user wants a new image, illustration, render, or visual concept.
- The user wants a model-specific image provider but the project should stay on CometAPI.
- The task benefits from repeatable image generation via a helper script instead of ad hoc API calls.

## Default Model Strategy

- Default to `gemini-3-pro-image-preview` unless the user explicitly asks for another image model.
- Use `gpt-image-1.5` for OpenAI-compatible image generation that usually returns inline image bytes.
- Use `dall-e-3` when the user specifically wants DALL-E style compatibility.
- Use `flux-2-pro` for Flux workflows that need CometAPI's Replicate-compatible route.

## How to Use

Run the helper script from this skill folder:

```bash
python scripts/generate_image.py "A retro-futurist travel poster for Shanghai"
python scripts/generate_image.py --model gpt-image-1.5 "A cute baby sea otter" assets/otter.png
python scripts/generate_image.py --model dall-e-3 --size 1024x1024 "A cinematic sci-fi skyline at sunset" output/dalle-city.png
python scripts/generate_image.py --model flux-2-pro --aspect-ratio 16:9 --resolution "2 MP" "Photoreal product shot of a premium espresso machine"
python scripts/generate_image.py --reference design/mockup.png --reference assets/logo.png "Turn these references into a launch poster"
```

## Reference Images

- Gemini accepts local file paths or remote URLs through `--reference`.
- Flux accepts URL-based references only. If the user gives local files, upload them somewhere accessible first or switch to Gemini.

## Output Behavior

- Gemini saves the first generated image locally and may also print model text output.
- GPT Image models may return `b64_json`, which the helper decodes to a file.
- DALL-E may return a hosted image URL; the helper downloads it automatically.
- Flux submits an async prediction, polls CometAPI until completion, then downloads the first output asset.

## Operational Rules

1. Use the helper instead of embedding raw API code in the conversation when the user wants an actual image artifact.
2. Keep outputs inside the user's workspace unless they ask for a different destination.
3. If the user does not provide an output path, let the helper create a timestamped filename in the current working directory.
4. If the user asks for a specific provider model that CometAPI supports, pass it through `--model` instead of changing services.
5. Authentication must come from `COMETAPI_KEY`.

## Notes for Maintainers

- The helper intentionally uses only the Python standard library so the copied skill remains portable.
- This skill is the baseline pattern for future CometAPI skills such as video, music, TTS, and image editing.