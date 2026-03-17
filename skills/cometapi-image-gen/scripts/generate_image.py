#!/usr/bin/env python3

"""Generate images through CometAPI across Gemini, GPT Image, DALL-E, and Flux."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
import time
from pathlib import Path
from typing import Any
from urllib import error, parse, request

BASE_URL = "https://api.cometapi.com"
DEFAULT_MODEL = "gemini-3-pro-image-preview"

OPENAI_IMAGE_MODELS = {
    "gpt-image-1",
    "gpt-image-1.5",
    "gpt-image-1-mini",
    "dall-e-3",
}

FLUX_MODEL_SLUGS = {
    "flux-2-pro": "black-forest-labs/flux-2-pro",
    "flux-2-flex": "black-forest-labs/flux-2-flex",
    "flux-2-max": "black-forest-labs/flux-2-max",
    "flux-2-dev": "black-forest-labs/flux-2-dev",
    "flux-kontext-max": "black-forest-labs/flux-kontext-max",
    "black-forest-labs/flux-2-pro": "black-forest-labs/flux-2-pro",
    "black-forest-labs/flux-2-flex": "black-forest-labs/flux-2-flex",
    "black-forest-labs/flux-2-max": "black-forest-labs/flux-2-max",
    "black-forest-labs/flux-2-dev": "black-forest-labs/flux-2-dev",
    "black-forest-labs/flux-kontext-max": "black-forest-labs/flux-kontext-max",
}


def main() -> int:
    args = build_parser().parse_args()
    api_key = os.environ.get("COMETAPI_KEY")
    if not api_key:
        print("COMETAPI_KEY is not set.", file=sys.stderr)
        return 1

    try:
        family = detect_family(args.model)
        if family == "gemini":
            output_path = generate_with_gemini(args, api_key)
        elif family == "openai-image":
            output_path = generate_with_openai_image(args, api_key)
        elif family == "flux":
            output_path = generate_with_flux(args, api_key)
        else:
            raise RuntimeError(f"Unsupported model family for {args.model}")
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(f"Image saved to: {output_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Generate images through CometAPI using Gemini, GPT Image, DALL-E, or Flux models."
        )
    )
    parser.add_argument("prompt", help="Text prompt describing the image to create.")
    parser.add_argument(
        "output",
        nargs="?",
        help="Optional output path. If omitted, a timestamped filename is created in the current directory.",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=(
            "CometAPI image model. Examples: gemini-3-pro-image-preview, gpt-image-1.5, "
            "dall-e-3, flux-2-pro."
        ),
    )
    parser.add_argument(
        "--reference",
        action="append",
        default=[],
        help="Local image path or remote URL to use as a reference. Can be passed multiple times.",
    )
    parser.add_argument(
        "--aspect-ratio",
        default="1:1",
        help="Aspect ratio for Gemini and Flux models, for example 1:1 or 16:9.",
    )
    parser.add_argument(
        "--image-size",
        default="4K",
        help="Gemini image size, for example 1K, 2K, or 4K.",
    )
    parser.add_argument(
        "--size",
        default="1024x1024",
        help="OpenAI-compatible image size, for example 1024x1024 or 1792x1024.",
    )
    parser.add_argument(
        "--quality",
        default="auto",
        help="OpenAI-compatible quality value. Use auto to omit it.",
    )
    parser.add_argument(
        "--style",
        default="auto",
        help="OpenAI-compatible style value. Use auto to omit it.",
    )
    parser.add_argument(
        "--response-format",
        choices=["auto", "url", "b64_json"],
        default="auto",
        help="OpenAI-compatible response format. Use auto to accept the model default.",
    )
    parser.add_argument(
        "--resolution",
        default="2 MP",
        help="Flux resolution, for example 1 MP, 2 MP, or 4 MP.",
    )
    parser.add_argument(
        "--output-format",
        choices=["jpg", "jpeg", "png"],
        default="jpg",
        help="Flux output format.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        help="Optional seed for Flux models.",
    )
    parser.add_argument(
        "--safety-tolerance",
        type=int,
        choices=range(0, 6),
        help="Flux safety tolerance from 0 to 5.",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=5,
        help="Polling interval in seconds for async providers such as Flux.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Max seconds to wait for async providers such as Flux.",
    )
    parser.add_argument(
        "--request-timeout",
        type=int,
        default=300,
        help="Timeout in seconds for each individual HTTP request.",
    )
    return parser


def detect_family(model: str) -> str:
    normalized = model.strip().lower()
    if normalized.startswith("gemini-") and "image" in normalized:
        return "gemini"
    if normalized in OPENAI_IMAGE_MODELS or normalized.startswith("gpt-image-"):
        return "openai-image"
    if normalized in FLUX_MODEL_SLUGS or "flux" in normalized:
        return "flux"
    raise RuntimeError(
        "Unsupported model. Use a Gemini image model, a GPT Image/DALL-E model, or a Flux model."
    )


def generate_with_gemini(args: argparse.Namespace, api_key: str) -> Path:
    parts: list[dict[str, Any]] = [{"text": args.prompt}]
    for reference in args.reference:
        parts.append(load_reference_as_inline_part(reference, args.request_timeout))

    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": {
                "aspectRatio": args.aspect_ratio,
                "imageSize": args.image_size,
            },
        },
    }

    url = f"{BASE_URL}/v1beta/models/{parse.quote(args.model, safe='-._')}:generateContent"
    status_code, response = request_json(
        "POST",
        url,
        headers={
            "x-goog-api-key": api_key,
            "Content-Type": "application/json",
        },
        body=payload,
        timeout=args.request_timeout,
    )
    ensure_success(status_code, response)

    candidates = response.get("candidates") or []
    if not candidates:
        raise RuntimeError(
            f"Gemini response did not include candidates: {json.dumps(response, ensure_ascii=True)}"
        )

    content = candidates[0].get("content") or {}
    response_parts = content.get("parts") or []
    text_chunks: list[str] = []

    for part in response_parts:
        if isinstance(part, dict) and part.get("text"):
            text_chunks.append(str(part["text"]))
        inline_data = part.get("inlineData") if isinstance(part, dict) else None
        if inline_data and inline_data.get("data"):
            mime_type = inline_data.get("mimeType") or "image/png"
            image_bytes = decode_base64(inline_data["data"])
            output_path = resolve_output_path(
                args.output, args.model, extension_for_mime(mime_type)
            )
            write_bytes(output_path, image_bytes)
            if text_chunks:
                print("\n".join(text_chunks), file=sys.stderr)
            return output_path

    raise RuntimeError(
        f"Gemini response did not include image bytes: {json.dumps(response, ensure_ascii=True)}"
    )


def generate_with_openai_image(args: argparse.Namespace, api_key: str) -> Path:
    payload: dict[str, Any] = {
        "model": args.model,
        "prompt": args.prompt,
        "n": 1,
        "size": args.size,
    }
    if args.quality != "auto":
        payload["quality"] = args.quality
    if args.style != "auto":
        payload["style"] = args.style
    if args.response_format != "auto":
        payload["response_format"] = args.response_format

    status_code, response = request_json(
        "POST",
        f"{BASE_URL}/v1/images/generations",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        body=payload,
        timeout=args.request_timeout,
    )
    ensure_success(status_code, response)

    items = response.get("data") or []
    if not items:
        raise RuntimeError(
            f"Image response did not include data items: {json.dumps(response, ensure_ascii=True)}"
        )

    item = items[0]
    revised_prompt = item.get("revised_prompt")
    if revised_prompt:
        print(f"Revised prompt: {revised_prompt}", file=sys.stderr)

    if item.get("b64_json"):
        output_path = resolve_output_path(args.output, args.model, ".png")
        write_bytes(output_path, decode_base64(item["b64_json"]))
        return output_path

    if item.get("url"):
        output_path = resolve_output_path(
            args.output, args.model, suffix_from_url(item["url"], default=".png")
        )
        download_to_path(item["url"], output_path, args.request_timeout)
        return output_path

    raise RuntimeError(
        f"Unsupported image payload: {json.dumps(item, ensure_ascii=True)}"
    )


def generate_with_flux(args: argparse.Namespace, api_key: str) -> Path:
    slug = FLUX_MODEL_SLUGS.get(args.model, args.model)
    if slug not in FLUX_MODEL_SLUGS.values():
        raise RuntimeError(
            "Unsupported Flux model. Try flux-2-pro, flux-2-flex, flux-2-max, flux-2-dev, or flux-kontext-max."
        )

    input_payload: dict[str, Any] = {
        "prompt": args.prompt,
        "aspect_ratio": args.aspect_ratio,
        "resolution": args.resolution,
        "output_format": args.output_format,
    }
    if args.seed is not None:
        input_payload["seed"] = args.seed
    if args.safety_tolerance is not None:
        input_payload["safety_tolerance"] = args.safety_tolerance
    if args.reference:
        if not all(is_url(reference) for reference in args.reference):
            raise RuntimeError(
                "Flux references must be remote URLs. Use Gemini for local reference images."
            )
        input_payload["input_images"] = args.reference

    status_code, create_response = request_json(
        "POST",
        f"{BASE_URL}/replicate/v1/models/{slug}/predictions",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        body={"input": input_payload},
        timeout=args.request_timeout,
    )
    ensure_success(status_code, create_response)

    prediction_id = create_response.get("id") or (
        create_response.get("data") or {}
    ).get("id")
    if not prediction_id:
        raise RuntimeError(
            f"Flux create response did not include a prediction id: {json.dumps(create_response, ensure_ascii=True)}"
        )

    print(f"Flux prediction created: {prediction_id}", file=sys.stderr)
    deadline = time.time() + args.timeout
    query_url = f"{BASE_URL}/replicate/v1/predictions/{prediction_id}"

    while time.time() < deadline:
        time.sleep(max(args.poll_interval, 1))
        status_code, query_response = request_json(
            "GET",
            query_url,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=args.request_timeout,
        )
        ensure_success(status_code, query_response)

        envelope = (
            query_response.get("data")
            if isinstance(query_response.get("data"), dict)
            else query_response
        )
        status_value = str(envelope.get("status", "")).upper()
        progress = envelope.get("progress", "N/A")

        if status_value == "SUCCESS":
            output_urls = normalize_output_urls(
                (envelope.get("data") or {}).get("output")
            )
            if not output_urls:
                raise RuntimeError(
                    f"Flux finished without output URLs: {json.dumps(query_response, ensure_ascii=True)}"
                )
            output_path = resolve_output_path(
                args.output,
                args.model,
                f".{normalize_output_format(args.output_format)}",
            )
            download_to_path(output_urls[0], output_path, args.request_timeout)
            return output_path

        if status_value in {"FAILED", "ERROR", "CANCELED", "CANCELLED"}:
            reason = (
                envelope.get("fail_reason") or envelope.get("error") or query_response
            )
            raise RuntimeError(f"Flux generation failed: {reason}")

        print(
            f"Flux status: {status_value or 'PENDING'} (progress: {progress})",
            file=sys.stderr,
        )

    raise RuntimeError(
        f"Flux prediction {prediction_id} did not finish within {args.timeout} seconds."
    )


def ensure_success(status_code: int, response: Any) -> None:
    if 200 <= status_code < 300:
        return
    raise RuntimeError(f"HTTP {status_code}: {json.dumps(response, ensure_ascii=True)}")


def request_json(
    method: str,
    url: str,
    headers: dict[str, str],
    body: dict[str, Any] | None = None,
    timeout: int = 120,
) -> tuple[int, Any]:
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    http_request = request.Request(url, data=data, method=method)
    for key, value in headers.items():
        http_request.add_header(key, value)

    try:
        with request.urlopen(http_request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            return response.getcode(), json.loads(raw) if raw else {}
    except error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = {"raw": raw}
        return exc.code, parsed
    except error.URLError as exc:
        raise RuntimeError(f"Request to {url} failed: {exc.reason}") from exc
    except TimeoutError as exc:
        raise RuntimeError(
            f"Request to {url} timed out after {timeout} seconds"
        ) from exc


def download_to_path(url: str, output_path: Path, timeout: int) -> None:
    http_request = request.Request(url, method="GET")
    try:
        with request.urlopen(http_request, timeout=timeout) as response:
            write_bytes(output_path, response.read())
    except error.URLError as exc:
        raise RuntimeError(f"Failed to download {url}: {exc.reason}") from exc


def load_reference_as_inline_part(
    reference: str, timeout: int
) -> dict[str, dict[str, str]]:
    if is_url(reference):
        http_request = request.Request(reference, method="GET")
        try:
            with request.urlopen(http_request, timeout=timeout) as response:
                raw = response.read()
                content_type = response.headers.get("Content-Type")
        except error.URLError as exc:
            raise RuntimeError(
                f"Failed to read reference URL {reference}: {exc.reason}"
            ) from exc
        mime_type = guess_mime_type(reference, content_type)
    else:
        path = Path(reference).expanduser().resolve()
        if not path.exists():
            raise RuntimeError(f"Reference image does not exist: {reference}")
        raw = path.read_bytes()
        mime_type = guess_mime_type(path.name)

    return {
        "inlineData": {
            "mimeType": mime_type,
            "data": base64.b64encode(raw).decode("ascii"),
        }
    }


def resolve_output_path(output_arg: str | None, model: str, extension: str) -> Path:
    extension = normalize_extension(extension)
    if output_arg:
        output_path = Path(output_arg).expanduser()
        if output_path.suffix:
            final_path = output_path
        else:
            final_path = output_path.with_suffix(extension)
    else:
        timestamp = time.strftime("%Y%m%d-%H%M%S")
        final_path = Path.cwd() / f"{sanitize_name(model)}-{timestamp}{extension}"

    final_path.parent.mkdir(parents=True, exist_ok=True)
    return final_path.resolve()


def write_bytes(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def normalize_output_urls(output: Any) -> list[str]:
    if isinstance(output, str) and output:
        return [output]
    if isinstance(output, list):
        return [item for item in output if isinstance(item, str) and item]
    return []


def decode_base64(value: str) -> bytes:
    try:
        return base64.b64decode(value)
    except ValueError as exc:
        raise RuntimeError("Failed to decode returned base64 image data.") from exc


def guess_mime_type(name: str, content_type: str | None = None) -> str:
    if content_type:
        return content_type.split(";", 1)[0].strip()
    guessed, _ = mimetypes.guess_type(name)
    return guessed or "image/png"


def extension_for_mime(mime_type: str) -> str:
    extension = mimetypes.guess_extension(mime_type) or ".png"
    return normalize_extension(extension)


def suffix_from_url(url: str, default: str) -> str:
    suffix = Path(parse.urlparse(url).path).suffix
    return normalize_extension(suffix or default)


def normalize_extension(extension: str) -> str:
    normalized = extension if extension.startswith(".") else f".{extension}"
    if normalized == ".jpe":
        return ".jpg"
    return normalized.lower()


def normalize_output_format(value: str) -> str:
    return "jpg" if value == "jpeg" else value


def sanitize_name(value: str) -> str:
    return (
        "".join(
            char if char.isalnum() or char in {"-", "_"} else "-" for char in value
        ).strip("-")
        or "image"
    )


def is_url(value: str) -> bool:
    parsed = parse.urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


if __name__ == "__main__":
    raise SystemExit(main())
