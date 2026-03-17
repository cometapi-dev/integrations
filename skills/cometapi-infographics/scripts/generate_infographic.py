#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import time
from pathlib import Path
from typing import Any
from urllib import error, request


BASE_URL = "https://api.cometapi.com"
MODEL = "gemini-3-pro-image-preview"

INFOGRAPHIC_TYPES = {
    "statistical": "Use large readable numbers, chart-like zones, comparisons, legends, and trend cues.",
    "timeline": "Use a clear chronological flow with milestone markers, dates, and directional progression.",
    "process": "Use step-by-step sequencing, directional arrows, and concise action labels.",
    "comparison": "Use a balanced side-by-side layout with matched categories and quick-scan contrasts.",
    "list": "Use numbered or icon-led sections with strong hierarchy and short readable copy.",
    "social": "Use bold headline treatment, highly scannable layout, and visual impact suitable for sharing.",
}

STYLE_PRESETS = {
    "corporate": "Professional corporate design with navy, slate, and restrained gold accents.",
    "healthcare": "Clean healthcare visual language with trustworthy blues and clinical clarity.",
    "technology": "Modern technology style with deep blues, cool neutrals, and subtle futuristic cues.",
    "education": "Clear educational design with friendly colors and strong explanatory hierarchy.",
    "marketing": "High-contrast marketing layout with bold focal points and strong callout sections.",
}

PALETTES = {
    "wong": "Use Wong's colorblind-safe palette.",
    "ibm": "Use IBM's colorblind-safe palette.",
    "tol": "Use Tol's qualitative colorblind-safe palette.",
}

DOC_TYPES = {
    "marketing": "Optimize for persuasive public-facing polish.",
    "report": "Optimize for professional report readability and credibility.",
    "presentation": "Optimize for slide readability at distance.",
    "social": "Optimize for fast scanning and social sharing.",
    "internal": "Optimize for internal clarity over visual spectacle.",
    "draft": "Optimize for fast concept iteration.",
    "default": "Optimize for a balanced professional infographic.",
}


def main() -> int:
    args = parse_args()
    api_key = os.environ.get("COMETAPI_KEY")
    if not api_key:
        print("COMETAPI_KEY is not set.")
        return 1

    facts = list(args.fact)
    if args.facts_file:
        facts.extend(load_facts_file(Path(args.facts_file)))

    rendered_prompt = build_prompt(args, facts)
    payload = {
        "contents": [{"role": "user", "parts": [{"text": rendered_prompt}]}],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": {
                "aspectRatio": args.aspect_ratio,
                "imageSize": args.image_size,
            },
        },
    }

    status_code, response = request_json(
        method="POST",
        url=f"{BASE_URL}/v1beta/models/{MODEL}:generateContent",
        headers={
            "x-goog-api-key": api_key,
            "Content-Type": "application/json",
        },
        body=payload,
        timeout=args.request_timeout,
    )
    if not 200 <= status_code < 300:
        print(json.dumps(response, indent=2, ensure_ascii=True))
        return 1

    image_part = first_image_part(response)
    if image_part is None:
        print("No image payload returned.")
        return 1

    output_path = resolve_output_path(args.output, image_part["mime_type"])
    output_path.write_bytes(base64.b64decode(image_part["data"]))
    metadata_path = write_metadata(args, facts, rendered_prompt, payload, output_path)

    print(f"Saved image to: {output_path}")
    print(f"MEDIA: {output_path}")
    print(f"Metadata saved to: {metadata_path}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate infographic-style images through CometAPI."
    )
    parser.add_argument("prompt", help="Topic or description for the infographic.")
    parser.add_argument("--output", required=True, help="Output image file path.")
    parser.add_argument(
        "--type",
        choices=sorted(INFOGRAPHIC_TYPES.keys()),
        default="list",
        help="Infographic type preset.",
    )
    parser.add_argument(
        "--style",
        choices=sorted(STYLE_PRESETS.keys()),
        default="technology",
        help="Visual style preset.",
    )
    parser.add_argument(
        "--palette",
        choices=sorted(PALETTES.keys()),
        default="wong",
        help="Colorblind-safe palette preset.",
    )
    parser.add_argument(
        "--doc-type",
        choices=sorted(DOC_TYPES.keys()),
        default="default",
        help="Document-context preset.",
    )
    parser.add_argument(
        "--fact",
        action="append",
        default=[],
        help="Exact fact to preserve. Repeatable.",
    )
    parser.add_argument(
        "--facts-file",
        help="Path to a text or JSON file containing source-grounded facts.",
    )
    parser.add_argument("--subtitle", help="Optional subtitle or framing line.")
    parser.add_argument(
        "--aspect-ratio", default="4:5", help="Aspect ratio such as 4:5, 9:16, or 16:9."
    )
    parser.add_argument(
        "--image-size",
        choices=["1K", "2K", "4K"],
        default="4K",
        help="Gemini image size.",
    )
    parser.add_argument(
        "--request-timeout", type=int, default=300, help="HTTP timeout in seconds."
    )
    return parser.parse_args()


def build_prompt(args: argparse.Namespace, facts: list[str]) -> str:
    sections = [
        "Create a polished infographic image.",
        f"Topic: {args.prompt}",
        f"Infographic type: {args.type}. {INFOGRAPHIC_TYPES[args.type]}",
        f"Visual style: {args.style}. {STYLE_PRESETS[args.style]}",
        f"Palette: {args.palette}. {PALETTES[args.palette]}",
        f"Document context: {args.doc_type}. {DOC_TYPES[args.doc_type]}",
        "Use strong information hierarchy, highly readable labels, and clear section separation.",
        "Avoid clutter. Keep text concise and visually scannable.",
    ]
    if args.subtitle:
        sections.append(f"Subtitle: {args.subtitle}")
    if facts:
        sections.append(
            "Only use the following source-grounded facts. Do not invent extra statistics, dates, or percentages:"
        )
        sections.extend(f"- {fact}" for fact in facts)
    else:
        sections.append(
            "If the request lacks exact figures, use qualitative phrasing instead of inventing statistics."
        )
    return "\n".join(sections)


def load_facts_file(path: Path) -> list[str]:
    if not path.exists():
        raise SystemExit(f"Facts file not found: {path}")
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return []
    if path.suffix.lower() == ".json":
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return [str(item).strip() for item in parsed if str(item).strip()]
        if isinstance(parsed, dict):
            return [f"{key}: {value}" for key, value in parsed.items()]
    return [line.strip("- ").strip() for line in raw.splitlines() if line.strip()]


def first_image_part(response: dict[str, Any]) -> dict[str, str] | None:
    candidates = response.get("candidates") or []
    if not candidates:
        return None
    content = candidates[0].get("content") or {}
    parts = content.get("parts") or []
    for part in parts:
        inline = part.get("inlineData") if isinstance(part, dict) else None
        if inline and inline.get("data"):
            return {
                "mime_type": inline.get("mimeType") or "image/png",
                "data": inline["data"],
            }
    return None


def resolve_output_path(output_arg: str, mime_type: str) -> Path:
    output_path = Path(output_arg).expanduser()
    suffix = output_path.suffix or (mimetypes.guess_extension(mime_type) or ".png")
    final_path = output_path if output_path.suffix else output_path.with_suffix(suffix)
    final_path.parent.mkdir(parents=True, exist_ok=True)
    return final_path.resolve()


def write_metadata(
    args: argparse.Namespace,
    facts: list[str],
    rendered_prompt: str,
    payload: dict[str, Any],
    output_path: Path,
) -> str:
    metadata_path = output_path.with_suffix(output_path.suffix + ".meta.json")
    metadata = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "provider": "cometapi",
        "model": MODEL,
        "topic": args.prompt,
        "subtitle": args.subtitle,
        "type": args.type,
        "style": args.style,
        "palette": args.palette,
        "doc_type": args.doc_type,
        "facts": facts,
        "rendered_prompt": rendered_prompt,
        "payload": payload,
        "output": str(output_path),
    }
    metadata_path.write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return str(metadata_path.resolve())


def request_json(
    method: str, url: str, headers: dict[str, str], body: dict[str, Any], timeout: int
) -> tuple[int, dict[str, Any]]:
    req = request.Request(url, data=json.dumps(body).encode("utf-8"), method=method)
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with request.urlopen(req, timeout=timeout) as response:
            return response.getcode(), json.loads(response.read().decode("utf-8"))
    except error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = {"raw": raw}
        return exc.code, parsed
    except error.URLError as exc:
        return 0, {"error": str(exc.reason)}
    except TimeoutError:
        return 0, {"error": f"Request timed out after {timeout} seconds"}


if __name__ == "__main__":
    raise SystemExit(main())
