#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any
from urllib import error, parse, request


BASE_URL = "https://api.cometapi.com"
DEFAULT_MODEL = "gemini-3-pro-image-preview"
SUPPORTED_MODELS = {
    "gemini-3-pro-image-preview",
    "gemini-3.1-flash-image-preview",
}
MAX_INPUT_IMAGES = 5
DEFAULT_TEMPLATE_PATH = Path(__file__).resolve().parents[1] / "assets" / "SYSTEM_TEMPLATE"

# Model-aware defaults: flash is tuned for speed, pro for quality.
MODEL_DEFAULTS = {
    "gemini-3-pro-image-preview": {"resolution": "2K", "parallel": 1, "delay": 2.0},
    "gemini-3.1-flash-image-preview": {"resolution": "1K", "parallel": 2, "delay": 1.5},
}


def main() -> int:
    args = parse_args()
    api_key = os.environ.get("COMETAPI_KEY")
    if not api_key:
        print("COMETAPI_KEY is not set.")
        return 1

    mode = resolve_mode(args.mode, args.input_image)
    input_records = [load_reference_record(reference, args.request_timeout) for reference in args.input_image]
    rendered_prompt = build_rendered_prompt(args, mode)
    system_instruction = load_system_instruction(args)
    base_output = resolve_base_output(args)

    results = run_generation_batch(
        args=args,
        api_key=api_key,
        rendered_prompt=rendered_prompt,
        system_instruction=system_instruction,
        input_records=input_records,
        base_output=base_output,
    )

    successful = [result for result in results if result["success"]]
    if not successful:
        for result in results:
            print(f"Variant {result['variant_index']:02d} failed: {result['error']}")
        return 1

    metadata_path = write_metadata(
        args=args,
        mode=mode,
        rendered_prompt=rendered_prompt,
        system_instruction=system_instruction,
        input_records=input_records,
        base_output=base_output,
        results=results,
    )

    for result in successful:
        if args.count > 1:
            print(f"Variant {result['variant_index']:02d}: success")
        for output in result["outputs"]:
            print(f"Saved image to: {output['path']}")
            print(f"MEDIA: {output['path']}")
    for result in results:
        if not result["success"]:
            print(f"Variant {result['variant_index']:02d} failed: {result['error']}")
    print(f"Metadata saved to: {metadata_path}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate, edit, or compose images through CometAPI using Gemini.")
    parser.add_argument("--prompt", required=True, help="Primary instruction for the generated image.")
    parser.add_argument("--model", default=DEFAULT_MODEL, choices=sorted(SUPPORTED_MODELS), help="Gemini model. Pro for quality, Flash for speed.")
    parser.add_argument("--output", help="Single output file path or base output name.")
    parser.add_argument("--output-dir", help="Directory for batch outputs.")
    parser.add_argument("--prefix", help="Filename prefix for batch generation.")
    parser.add_argument("--input-image", action="append", default=[], help=f"Local image path or URL to use as a reference. Repeatable, maximum {MAX_INPUT_IMAGES}.")
    parser.add_argument("--mode", choices=["auto", "generate", "edit", "compose"], default="auto", help="Workflow mode.")
    parser.add_argument("--resolution", choices=["1K", "2K", "4K"], default=None, help="Output resolution. Default: 2K for Pro, 1K for Flash.")
    parser.add_argument("--aspect-ratio", default="1:1", help="Aspect ratio such as 1:1 or 16:9.")
    parser.add_argument("--style-note", action="append", default=[], help="Optional art direction note. Repeatable.")
    parser.add_argument("--layout-note", action="append", default=[], help="Optional layout/composition note. Repeatable.")
    parser.add_argument("--preserve-note", action="append", default=[], help="Important visual details to preserve from the source images.")
    parser.add_argument("--count", type=int, default=1, help="How many variants to generate.")
    parser.add_argument("--parallel", type=int, default=None, help="Maximum concurrent requests. Default: 1 for Pro, 2 for Flash.")
    parser.add_argument("--delay", type=float, default=None, help="Delay in seconds between batch requests. Default: 2.0 for Pro, 1.5 for Flash.")
    parser.add_argument("--system-template", help="Optional path to a system template file. Defaults to assets/SYSTEM_TEMPLATE if it exists.")
    parser.add_argument("--no-system-template", action="store_true", help="Disable loading any system template.")
    parser.add_argument("--request-timeout", type=int, default=300, help="HTTP timeout in seconds.")
    args = parser.parse_args()

    # Apply model-aware defaults for any unset args.
    defaults = MODEL_DEFAULTS.get(args.model, MODEL_DEFAULTS[DEFAULT_MODEL])
    if args.resolution is None:
        args.resolution = defaults["resolution"]
    if args.parallel is None:
        args.parallel = defaults["parallel"]
    if args.delay is None:
        args.delay = defaults["delay"]

    if len(args.input_image) > MAX_INPUT_IMAGES:
        parser.error(f"Too many input images: {len(args.input_image)} > {MAX_INPUT_IMAGES}")
    if args.count < 1:
        parser.error("--count must be at least 1")
    if args.parallel < 1:
        parser.error("--parallel must be at least 1")
    return args


def resolve_mode(mode: str, input_images: list[str]) -> str:
    if mode != "auto":
        if mode == "edit" and not input_images:
            raise SystemExit("Edit mode requires at least one --input-image.")
        if mode == "compose" and len(input_images) < 2:
            raise SystemExit("Compose mode requires at least two --input-image values.")
        return mode
    if not input_images:
        return "generate"
    if len(input_images) == 1:
        return "edit"
    return "compose"


def build_rendered_prompt(args: argparse.Namespace, mode: str) -> str:
    is_flash = "flash" in args.model
    lines = []
    if mode == "generate":
        if is_flash:
            lines.append("Create a clear, useful, quickly reviewable image concept that fulfills the user's request.")
        else:
            lines.append("Create a polished high-quality final image with strong composition, clear subject hierarchy, and refined detail.")
    elif mode == "edit":
        if is_flash:
            lines.append("Edit the provided source image while keeping the important subject identity and clearly recognizable details intact unless the instruction explicitly asks for change.")
        else:
            lines.append("Edit the provided source image while preserving the subject identity, silhouette, and key recognizable details unless the instruction explicitly asks for transformation.")
    else:
        if is_flash:
            lines.append("Combine the provided source images into one coherent fast-iteration concept while preserving the key recognizable details that matter from each source.")
        else:
            lines.append("Combine the provided source images into one coherent premium composition while preserving the recognizable details that matter from each source.")

    lines.append(f"User request: {args.prompt}")
    if args.style_note:
        lines.append("Style direction:")
        lines.extend(f"- {note}" for note in args.style_note)
    if args.layout_note:
        lines.append("Layout direction:")
        lines.extend(f"- {note}" for note in args.layout_note)
    if args.preserve_note:
        lines.append("Preserve these source details:")
        lines.extend(f"- {note}" for note in args.preserve_note)
    if mode == "compose":
        if is_flash:
            lines.append("Use all provided images meaningfully. Keep the final concept easy to evaluate at a glance.")
        else:
            lines.append("Use all provided images meaningfully. Keep scale, perspective, lighting, and style consistent across the final scene.")
    if is_flash:
        lines.append("Return a strong final image only.")
    else:
        lines.append("Return a high-quality final image only.")
    return "\n".join(lines)


def load_system_instruction(args: argparse.Namespace) -> str | None:
    if args.no_system_template:
        return None
    candidate = Path(args.system_template).expanduser() if args.system_template else DEFAULT_TEMPLATE_PATH
    if not candidate.exists():
        return None
    text = candidate.read_text(encoding="utf-8").strip()
    return text or None


def load_reference_record(reference: str, timeout: int) -> dict[str, Any]:
    if is_url(reference):
        req = request.Request(reference, method="GET")
        try:
            with request.urlopen(req, timeout=timeout) as response:
                raw = response.read()
                mime_type = response.headers.get("Content-Type", "image/png").split(";", 1)[0]
        except error.URLError as exc:
            raise SystemExit(f"Failed to fetch input image URL {reference}: {exc.reason}") from exc
        source = {"type": "url", "value": reference}
    else:
        path = Path(reference).expanduser().resolve()
        if not path.exists():
            raise SystemExit(f"Input image not found: {reference}")
        raw = path.read_bytes()
        mime_type = mimetypes.guess_type(path.name)[0] or "image/png"
        source = {"type": "file", "value": str(path)}

    return {
        "source": source,
        "mime_type": mime_type,
        "size_bytes": len(raw),
        "sha256": sha256_bytes(raw),
        "part": {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(raw).decode("ascii")}},
    }


def resolve_base_output(args: argparse.Namespace) -> Path:
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    if args.output:
        output = Path(args.output).expanduser()
        output.parent.mkdir(parents=True, exist_ok=True)
        return output
    output_dir = Path(args.output_dir).expanduser() if args.output_dir else Path.cwd()
    output_dir.mkdir(parents=True, exist_ok=True)
    prefix = args.prefix or f"cometapi-nano-banana-{timestamp}"
    return output_dir / prefix


def run_generation_batch(args: argparse.Namespace, api_key: str, rendered_prompt: str, system_instruction: str | None, input_records: list[dict[str, Any]], base_output: Path) -> list[dict[str, Any]]:
    common_payload = build_payload(rendered_prompt, system_instruction, input_records, args.aspect_ratio, args.resolution)
    variants = list(range(1, args.count + 1))
    results: list[dict[str, Any]] = []
    if args.count == 1 or args.parallel == 1:
        for variant_index in variants:
            if variant_index > 1 and args.delay > 0:
                time.sleep(args.delay)
            results.append(generate_variant(api_key, args.model, common_payload, args.request_timeout, base_output, variant_index, args.count))
        return results
    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = []
        for variant_index in variants:
            futures.append(executor.submit(generate_variant, api_key, args.model, common_payload, args.request_timeout, base_output, variant_index, args.count))
            if args.delay > 0 and variant_index < args.count:
                time.sleep(args.delay)
        for future in as_completed(futures):
            results.append(future.result())
    return sorted(results, key=lambda item: item["variant_index"])


def build_payload(rendered_prompt: str, system_instruction: str | None, input_records: list[dict[str, Any]], aspect_ratio: str, resolution: str) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "contents": [{"role": "user", "parts": [{"text": rendered_prompt}] + [record["part"] for record in input_records]}],
        "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": aspect_ratio, "imageSize": resolution}},
    }
    if system_instruction:
        payload["systemInstruction"] = {"parts": [{"text": system_instruction}]}
    return payload


def generate_variant(api_key: str, model: str, payload: dict[str, Any], timeout: int, base_output: Path, variant_index: int, total_variants: int) -> dict[str, Any]:
    status_code, response = request_json(method="POST", url=f"{BASE_URL}/v1beta/models/{model}:generateContent", headers={"x-goog-api-key": api_key, "Content-Type": "application/json"}, body=payload, timeout=timeout)
    if not 200 <= status_code < 300:
        return {"variant_index": variant_index, "success": False, "error": json.dumps(response, ensure_ascii=True), "outputs": []}
    image_parts = extract_image_parts(response)
    if not image_parts:
        return {"variant_index": variant_index, "success": False, "error": "No image payload returned.", "outputs": []}
    outputs = save_variant_images(base_output, image_parts, variant_index, total_variants)
    return {"variant_index": variant_index, "success": True, "error": None, "outputs": outputs}


def extract_image_parts(response: dict[str, Any]) -> list[dict[str, str]]:
    candidates = response.get("candidates") or []
    if not candidates:
        return []
    content = candidates[0].get("content") or {}
    parts = content.get("parts") or []
    images: list[dict[str, str]] = []
    for part in parts:
        inline = part.get("inlineData") if isinstance(part, dict) else None
        if inline and inline.get("data"):
            images.append({"mime_type": inline.get("mimeType") or "image/png", "data": inline["data"]})
    return images


def save_variant_images(base_output: Path, images: list[dict[str, str]], variant_index: int, total_variants: int) -> list[dict[str, Any]]:
    base_output.parent.mkdir(parents=True, exist_ok=True)
    outputs: list[dict[str, Any]] = []
    for image_index, image in enumerate(images, start=1):
        suffix = normalize_suffix(base_output.suffix or (mimetypes.guess_extension(image["mime_type"]) or ".png"))
        if total_variants == 1 and len(images) == 1:
            path = base_output.with_suffix(suffix)
        elif total_variants > 1 and len(images) == 1:
            path = base_output.with_name(f"{base_output.stem}-{variant_index:02d}{suffix}")
        elif total_variants == 1:
            path = base_output.with_name(f"{base_output.stem}-{image_index:02d}{suffix}")
        else:
            path = base_output.with_name(f"{base_output.stem}-{variant_index:02d}-{image_index:02d}{suffix}")
        raw = base64.b64decode(image["data"])
        path.write_bytes(raw)
        outputs.append({"path": str(path.resolve()), "mime_type": image["mime_type"], "sha256": sha256_bytes(raw), "size_bytes": len(raw)})
    return outputs


def write_metadata(args: argparse.Namespace, mode: str, rendered_prompt: str, system_instruction: str | None, input_records: list[dict[str, Any]], base_output: Path, results: list[dict[str, Any]]) -> str:
    metadata_path = base_output.with_name(f"{base_output.stem}.meta.json")
    metadata = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "provider": "cometapi",
        "model": args.model,
        "mode": mode,
        "prompt": args.prompt,
        "rendered_prompt": rendered_prompt,
        "style_notes": args.style_note,
        "layout_notes": args.layout_note,
        "preserve_notes": args.preserve_note,
        "count": args.count,
        "parallel": args.parallel,
        "delay": args.delay,
        "resolution": args.resolution,
        "aspect_ratio": args.aspect_ratio,
        "system_instruction": system_instruction,
        "system_template_path": None if args.no_system_template else str((Path(args.system_template).expanduser() if args.system_template else DEFAULT_TEMPLATE_PATH)),
        "input_images": [{"source": record["source"], "mime_type": record["mime_type"], "sha256": record["sha256"], "size_bytes": record["size_bytes"]} for record in input_records],
        "results": results,
    }
    metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return str(metadata_path.resolve())


def request_json(method: str, url: str, headers: dict[str, str], body: dict[str, Any], timeout: int) -> tuple[int, dict[str, Any]]:
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


def is_url(value: str) -> bool:
    parsed = parse.urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def normalize_suffix(value: str) -> str:
    suffix = value if value.startswith(".") else f".{value}"
    return ".jpg" if suffix.lower() == ".jpe" else suffix.lower()


if __name__ == "__main__":
    raise SystemExit(main())
