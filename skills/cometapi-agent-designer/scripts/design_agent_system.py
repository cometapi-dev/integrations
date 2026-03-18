#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import time
from pathlib import Path
from typing import Any
from urllib import error, request


BASE_URL = "https://api.cometapi.com/v1/chat/completions"
DEFAULT_MODEL = "gpt-4.1-mini"


def main() -> int:
    args = parse_args()
    api_key = os.environ.get("COMETAPI_KEY")
    if not api_key:
        print("COMETAPI_KEY is not set.")
        return 1

    output_path = resolve_output_path(args.output)
    system_prompt = build_system_prompt()
    user_prompt = build_user_prompt(args)
    payload = {
        "model": args.model,
        "temperature": args.temperature,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    }

    started_at = time.time()
    status_code, response = request_json(
        method="POST",
        url=BASE_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        body=payload,
        timeout=args.request_timeout,
    )
    duration_seconds = round(time.time() - started_at, 2)
    if not 200 <= status_code < 300:
        print(json.dumps(response, indent=2, ensure_ascii=True))
        return 1

    architecture_markdown = extract_text_response(response).strip()
    if not architecture_markdown:
        print("No text architecture returned.")
        return 1

    output_path.write_text(architecture_markdown + "\n", encoding="utf-8")
    mermaid_path = extract_mermaid_diagram(architecture_markdown, output_path)
    metadata_path = write_metadata(
        args=args,
        output_path=output_path,
        mermaid_path=mermaid_path,
        duration_seconds=duration_seconds,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        payload=payload,
    )

    print(f"Architecture saved to: {output_path}")
    print(f"ARTIFACT: {output_path}")
    if mermaid_path is not None:
        print(f"Mermaid saved to: {mermaid_path}")
        print(f"ARTIFACT: {mermaid_path}")
    print(f"Metadata saved to: {metadata_path}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Design a multi-agent system architecture through CometAPI.")
    parser.add_argument("--goal", required=True, help="High-level goal for the agent system.")
    parser.add_argument("--description", default="", help="Optional fuller description of the problem space.")
    parser.add_argument("--task", action="append", default=[], help="Task the system must handle. Repeatable.")
    parser.add_argument("--constraint", action="append", default=[], help="Constraint the architecture must respect. Repeatable.")
    parser.add_argument("--integration", action="append", default=[], help="Integration or system dependency to account for. Repeatable.")
    parser.add_argument("--safety-requirement", action="append", default=[], help="Safety or guardrail requirement. Repeatable.")
    parser.add_argument("--brief-file", help="Optional text file containing additional planning context.")
    parser.add_argument("--team-size", type=int, default=3, help="Preferred number of core agents.")
    parser.add_argument("--pattern-preference", choices=["auto", "single_agent", "supervisor", "swarm", "hierarchical", "pipeline"], default="auto", help="Optional coordination pattern preference.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="CometAPI text model to use.")
    parser.add_argument("--temperature", type=float, default=0.2, help="Sampling temperature.")
    parser.add_argument("--request-timeout", type=int, default=300, help="HTTP timeout in seconds.")
    parser.add_argument("--output", required=True, help="Output Markdown path.")
    return parser.parse_args()


def resolve_output_path(value: str) -> Path:
    output_path = Path(value).expanduser()
    if not output_path.suffix:
        output_path = output_path.with_suffix(".md")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return output_path.resolve()


def build_system_prompt() -> str:
    return (
        "You are a systems architect designing pragmatic multi-agent workflows for CometAPI users. "
        "Return concise, implementation-oriented Markdown with these exact headings: "
        "# System Summary, ## Recommended Pattern, ## Agent Roles, ## Communication Topology, "
        "## Guardrails, ## Tool Interfaces, ## Implementation Roadmap, ## Mermaid Diagram. "
        "Under Mermaid Diagram include exactly one fenced mermaid code block. "
        "Favor realistic small-team architectures and explain how CometAPI acts as the model-routing layer."
    )


def build_user_prompt(args: argparse.Namespace) -> str:
    sections = [
        f"Goal: {args.goal}",
        f"Preferred core agent count: {args.team_size}",
        f"Pattern preference: {args.pattern_preference}",
    ]
    if args.description:
        sections.append(f"Description: {args.description}")
    if args.task:
        sections.append("Tasks:")
        sections.extend(f"- {item}" for item in args.task)
    if args.constraint:
        sections.append("Constraints:")
        sections.extend(f"- {item}" for item in args.constraint)
    if args.integration:
        sections.append("Integrations:")
        sections.extend(f"- {item}" for item in args.integration)
    if args.safety_requirement:
        sections.append("Safety requirements:")
        sections.extend(f"- {item}" for item in args.safety_requirement)
    if args.brief_file:
        brief_path = Path(args.brief_file).expanduser().resolve()
        if not brief_path.exists():
            raise SystemExit(f"Brief file not found: {brief_path}")
        sections.append("Additional brief:")
        sections.append(brief_path.read_text(encoding="utf-8").strip())
    sections.append(
        "Make the architecture directly usable by an engineering team. Keep it specific enough to implement, but do not generate application code."
    )
    return "\n".join(sections)


def extract_text_response(response: dict[str, Any]) -> str:
    choices = response.get("choices") or []
    if not choices:
        return ""
    message = (choices[0].get("message") or {}).get("content", "")
    if isinstance(message, str):
        return message
    if isinstance(message, list):
        chunks = []
        for item in message:
            if isinstance(item, dict) and item.get("type") == "text":
                chunks.append(item.get("text", ""))
        return "\n".join(chunks)
    return ""


def extract_mermaid_diagram(markdown_text: str, output_path: Path) -> Path | None:
    match = re.search(r"```mermaid\s*(.*?)```", markdown_text, re.DOTALL | re.IGNORECASE)
    if not match:
        return None
    mermaid_text = match.group(1).strip() + "\n"
    mermaid_path = output_path.with_suffix(".mmd")
    mermaid_path.write_text(mermaid_text, encoding="utf-8")
    return mermaid_path


def write_metadata(
    args: argparse.Namespace,
    output_path: Path,
    mermaid_path: Path | None,
    duration_seconds: float,
    system_prompt: str,
    user_prompt: str,
    payload: dict[str, Any],
) -> str:
    markdown_bytes = output_path.read_bytes()
    metadata_path = output_path.with_suffix(output_path.suffix + ".meta.json")
    metadata = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "provider": "cometapi",
        "endpoint": "/v1/chat/completions",
        "model": args.model,
        "duration_seconds": duration_seconds,
        "inputs": {
            "goal": args.goal,
            "description": args.description,
            "tasks": args.task,
            "constraints": args.constraint,
            "integrations": args.integration,
            "safety_requirements": args.safety_requirement,
            "team_size": args.team_size,
            "pattern_preference": args.pattern_preference,
            "brief_file": args.brief_file,
        },
        "system_prompt": system_prompt,
        "user_prompt": user_prompt,
        "payload": payload,
        "outputs": {
            "markdown": {
                "path": str(output_path),
                "sha256": hashlib.sha256(markdown_bytes).hexdigest(),
                "size_bytes": len(markdown_bytes),
            },
            "mermaid": None if mermaid_path is None else str(mermaid_path),
        },
    }
    metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return str(metadata_path)


def request_json(method: str, url: str, headers: dict[str, str], body: dict[str, Any], timeout: int) -> tuple[int, dict[str, Any]]:
    http_request = request.Request(url, data=json.dumps(body).encode("utf-8"), method=method)
    for key, value in headers.items():
        http_request.add_header(key, value)
    try:
        with request.urlopen(http_request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            return response.getcode(), json.loads(raw) if raw else {}
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