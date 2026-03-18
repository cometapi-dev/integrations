---
name: cometapi-infographics
description: |
  Create structured infographic-style images through CometAPI using a prompt builder
  that preserves factual grounding. Use this whenever the user mentions infographics,
  data visualization images, timelines, comparison charts, process diagrams, list graphics,
  statistical summaries, social media data posts, presentation visuals, fact sheets,
  or any task where structured information needs to become a visual. Also trigger when
  the user has specific facts or statistics they want rendered as an image rather than
  a code-based chart. If the output is meant to tell a data story as a single image
  (not an interactive chart), this skill is the right choice.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# CometAPI Infographics

This skill generates infographic-quality images where structured data and facts are
the primary content. Unlike generic image generation, the helper builds a specialized
prompt that guides the model toward infographic layouts (timelines, comparisons, lists,
statistical summaries) and optionally locks the model to user-supplied facts so it
doesn't hallucinate statistics.

Default model: `gemini-3-pro-image-preview` — chosen because it handles text-heavy
image generation better than most alternatives.

## How It Works

The helper script constructs a structured prompt from three inputs:
1. **Topic** — what the infographic is about.
2. **Type** — the layout structure (list, timeline, comparison, statistical, process).
3. **Facts** — optional user-supplied data points.

When facts are provided, the prompt explicitly tells the model "use only these facts,
do not invent additional statistics." This prevents the model from hallucinating data
points that look authoritative but are fabricated. When facts aren't provided, the
prompt uses qualitative language instead.

## Usage Examples

**Example 1 — Simple list infographic:**
```bash
python scripts/generate_infographic.py "5 benefits of regular exercise" \
  --type list --output exercise.png
```
Output: A list-style infographic image + sidecar metadata JSON.

**Example 2 — Statistical infographic with grounded facts:**
```bash
python scripts/generate_infographic.py "Global AI market growth" \
  --type statistical --style technology \
  --fact "2025 market size: $391 billion" \
  --fact "Projected CAGR: 35.9%" \
  --output ai-market.png
```
Output: The model uses exactly the provided statistics — no fabricated data.

**Example 3 — Timeline from a facts file:**
```bash
python scripts/generate_infographic.py "History of machine learning breakthroughs" \
  --type timeline --style education \
  --facts-file notes/ml_timeline.txt \
  --output ml-timeline.png
```
Output: A timeline infographic grounded in the facts from the file.

## Configuration

| Flag | Purpose | Default |
|------|---------|--------|
| `--type` | Layout structure: list, timeline, comparison, statistical, process | `list` |
| `--style` | Visual theme: technology, education, business, health, etc. | none |
| `--fact` | A single fact to include (repeatable) | none |
| `--facts-file` | Path to a text file with one fact per line | none |
| `--output` | Output image path | Timestamped filename in cwd |

## Output and Traceability

Every run produces:
1. The infographic image.
2. A sidecar metadata JSON recording the rendered prompt, all supplied facts, presets used, and output path.

The metadata exists so the agent (or user) can trace exactly what facts went into the
image — particularly important when the infographic is used in presentations or reports.

## Constraints

- This skill generates **images of infographics**, not interactive charts or code-based
  visualizations. If the user wants a Matplotlib chart or a D3 dashboard, use a code
  generation workflow instead.
- If the request is for a scientific schematic or technical diagram with precise
  measurements, a specialized diagram skill would serve better.
- For general illustrations without data structure, use `cometapi-image-gen` or the
  Nano Banana family instead.