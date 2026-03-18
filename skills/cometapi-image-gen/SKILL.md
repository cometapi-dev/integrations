---
name: cometapi-image-gen
description: |
  Generate images through CometAPI using multiple model backends — Gemini, GPT Image,
  DALL-E, and Flux — with a single portable helper script. Use this skill whenever the
  user mentions illustrations, concept art, icons, hero images, posters, banners,
  product renders, visual mockups, social media graphics, thumbnails, book covers,
  multi-reference composition, or any task that produces a visual asset. Also trigger
  when the user wants to compare outputs from different image models or needs a specific
  provider but wants to stay on CometAPI. If the user mentions "image" and an AI model
  in the same breath, this skill almost certainly applies.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# CometAPI Image Generation

This skill routes image generation through CometAPI so you can switch between Gemini,
GPT Image, DALL-E, and Flux without changing your workflow. A single helper script
handles the provider-specific quirks — different response formats, async polling,
base64 decoding — so the agent just picks a model and runs the command.

## Model Selection

Different models have different strengths. Pick based on what the user needs:

| Model | Best for | Why |
|-------|----------|-----|
| `gemini-3-pro-image-preview` (default) | General illustration, multi-reference composition | Highest quality, accepts local file references |
| `gpt-image-1.5` | OpenAI-style generation | Returns inline base64, good for programmatic pipelines |
| `dall-e-3` | DALL-E aesthetic | Strong at creative interpretation of prompts |
| `flux-2-pro` | Photorealistic product shots | Replicate-compatible async workflow, URL-based references |

Default to Gemini unless the user explicitly asks for another model — it gives the
best balance of quality and flexibility, especially for reference-based work.

## Usage Examples

**Example 1 — Simple prompt-to-image:**
```bash
python scripts/generate_image.py "A retro-futurist travel poster for Shanghai"
```
Output: Saves a PNG with a timestamped filename + sidecar metadata JSON.

**Example 2 — Specific model with output path:**
```bash
python scripts/generate_image.py --model gpt-image-1.5 "A cute baby sea otter" assets/otter.png
```
Output: Decodes base64 response and saves to `assets/otter.png`.

**Example 3 — Multi-reference composition (Gemini):**
```bash
python scripts/generate_image.py \
  --reference design/mockup.png \
  --reference assets/logo.png \
  "Turn these references into a launch poster"
```
Output: Gemini reads the reference images and generates a composed result.

**Example 4 — Flux photorealistic with aspect ratio:**
```bash
python scripts/generate_image.py --model flux-2-pro --aspect-ratio 16:9 \
  --resolution "2 MP" "Photoreal product shot of a premium espresso machine"
```
Output: Submits an async prediction, polls until complete, downloads the result.

## How the Helper Works

The script detects which model family you're using and calls the right CometAPI endpoint:

- **Gemini** → native `POST /v1beta/models/{model}:generateContent` with `x-goog-api-key` header.
  Accepts local files (base64-encoded inline) and URLs. Saves the first image part from the response.
- **GPT Image** → OpenAI-compat `POST /v1/images/generations`. Returns `b64_json` which the helper decodes.
- **DALL-E** → OpenAI-compat endpoint. May return a hosted URL; the helper downloads it automatically.
- **Flux** → Replicate-compat `POST /v1/predictions`. Async workflow: submit, poll, download first output asset.

The helper uses only the Python standard library so it stays portable after the skill
folder is copied into any agent ecosystem.

## Reference Images

Gemini accepts local file paths or remote URLs through `--reference`. The helper reads
local files and base64-encodes them into the request body.

Flux accepts URL-based references only. If the user gives local files and wants Flux,
either upload them somewhere accessible first or switch to Gemini.

## Output Behavior

Every run produces:
1. The generated image file (PNG or format returned by the model).
2. A sidecar metadata JSON with the prompt, model, timestamp, and output path.

If no `--output` path is given, the helper creates a timestamped filename in the
current working directory. Keep outputs in the workspace unless the user says otherwise.

## Related Skills

- For Nano Banana-style workflows (edit, compose, batch variants with Gemini Pro or Flash), use `cometapi-nano-banana`.
- For structured infographics (timelines, comparisons, data stories), use `cometapi-infographics`.
- This skill is the right choice when the user wants a straightforward prompt-to-image generation with model flexibility.