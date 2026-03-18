---
name: cometapi-nano-banana
description: |
  Generate, edit, compose, and batch-iterate images through CometAPI using Gemini
  in a Nano Banana workflow. Use this whenever the user wants Gemini image generation,
  natural-language image editing, multi-image composition, batch variant exploration,
  or any visual task where Gemini is the right model. Trigger for: "generate an image",
  "edit this photo", "combine these images", "make me variations", "Nano Banana",
  "quick draft", "final quality", reference-guided generation, or any visual task
  that needs Gemini. Two models are available: Pro (default, highest quality) and
  Flash (fast drafts, rapid ideation). If the user just says "make me an image"
  without specifying a model, this skill applies.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# CometAPI Nano Banana

Nano Banana is a focused image workflow built on Gemini via CometAPI. It handles three
modes — generate, edit, and compose — from a single helper script, with batch variant
support, model selection, and full prompt traceability through sidecar metadata.

## Model Selection

Two Gemini models serve different stages of a creative workflow:

| Model | Flag | Best for | Why |
|-------|------|----------|-----|
| `gemini-3-pro-image-preview` (default) | `--model gemini-3-pro-image-preview` | Final assets, polished edits, production visuals | Highest quality; defaults to 2K resolution, conservative parallelism |
| `gemini-3.1-flash-image-preview` | `--model gemini-3.1-flash-image-preview` | Quick drafts, ideation, batch exploration | Faster generation; defaults to 1K resolution, higher parallelism |

Typical flow: explore with Flash → settle on a direction → finalize with Pro.

Default to Pro unless the user explicitly asks for speed, drafts, or exploration.

## Usage Examples

**Example 1 — Prompt-only generation (Pro, default):**
```bash
python scripts/generate_image.py \
  --prompt "A cinematic sunset over snow-capped mountains" \
  --output sunset.png
```

**Example 2 — Fast draft exploration (Flash):**
```bash
python scripts/generate_image.py \
  --model gemini-3.1-flash-image-preview \
  --prompt "Three directions for a comet-themed app hero illustration" \
  --count 3 --parallel 3 \
  --output-dir drafts --prefix hero-draft
```

**Example 3 — Natural-language image edit:**
```bash
python scripts/generate_image.py \
  --mode edit \
  --prompt "Replace the sky with a dramatic aurora" \
  --input-image input.jpg \
  --output aurora.png
```

**Example 4 — Multi-image composition:**
```bash
python scripts/generate_image.py \
  --mode compose \
  --prompt "Combine these people into a single studio portrait" \
  --input-image face1.jpg \
  --input-image face2.jpg \
  --output composite.png
```

**Example 5 — High-quality publication asset:**
```bash
python scripts/generate_image.py \
  --prompt "A cinematic startup launch poster with a comet emblem" \
  --aspect-ratio 4:5 \
  --resolution 2K \
  --output launch-poster.png
```

**Example 6 — Batch variants:**
```bash
python scripts/generate_image.py \
  --prompt "Create three poster variations from these references" \
  --input-image subject.png \
  --input-image logo.png \
  --count 3 --parallel 2 \
  --output-dir variants --prefix launch-poster
```

## How the Helper Works

The script calls CometAPI's native Gemini endpoint
(`POST /v1beta/models/{model}:generateContent` with `x-goog-api-key` header)
because Gemini's image generation returns richer results through its native API
than the OpenAI-compat shim.

The model is selected via `--model`. Defaults for resolution, parallelism, and delay
auto-adjust based on which model is chosen — Pro optimizes for quality, Flash for speed.

## Prompt Controls

| Flag | Purpose |
|------|--------|
| `--model` | `gemini-3-pro-image-preview` (quality) or `gemini-3.1-flash-image-preview` (speed) |
| `--style-note` | Art direction without rewriting the core prompt |
| `--layout-note` | Composition structure and visual hierarchy |
| `--preserve-note` | What to keep recognizable from source images |
| `--resolution` | `1K`, `2K`, `4K` — auto-set per model if omitted |
| `--aspect-ratio` | e.g., `16:9`, `4:5`, `1:1` |
| `--count` | Number of variants to generate |
| `--parallel` | Concurrent generation threads |

Edit `assets/SYSTEM_TEMPLATE` to set a project-wide default style.

## Output and Traceability

Every run produces:
1. Generated image(s) in the workspace.
2. `MEDIA: <path>` printed per image.
3. Sidecar metadata JSON with the rendered prompt, model, mode, input references,
   SHA-256 hashes, and output paths.

## Related Skills

- For multi-model generation (GPT Image, DALL-E, Flux), use `cometapi-image-gen`.
- For structured infographics (timelines, comparisons), use `cometapi-infographics`.
- For model-flexible generation (GPT Image, DALL-E, Flux), use `cometapi-image-gen`.