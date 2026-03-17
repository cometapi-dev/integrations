#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
SKILLS_ROOT = REPO_ROOT / "skills"


def main() -> int:
    args = parse_args()
    if not os.environ.get("COMETAPI_KEY"):
        print("COMETAPI_KEY is not set.", file=sys.stderr)
        return 1

    output_root = args.output_dir.expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    run_root = output_root / time.strftime("%Y%m%d-%H%M%S")
    run_root.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "output_root": str(run_root),
        "tests": [],
    }
    results_by_name: dict[str, dict[str, Any]] = {}

    image_gen_output = run_root / "cometapi-image-gen-gemini.png"
    test_result = run_case(
        name="cometapi-image-gen-gemini",
        command=[
            sys.executable,
            str(SKILLS_ROOT / "cometapi-image-gen" / "scripts" / "generate_image.py"),
            "--model",
            "gemini-3-pro-image-preview",
            "--image-size",
            "1K",
            "--request-timeout",
            "300",
            "A flat blue comet icon on a white background, clean vector style",
            str(image_gen_output),
        ],
        expected_paths=[image_gen_output],
    )
    report["tests"].append(test_result)
    results_by_name[test_result["name"]] = test_result

    openai_output = run_root / "cometapi-image-gen-gpt-image.png"
    test_result = run_case(
        name="cometapi-image-gen-gpt-image",
        command=[
            sys.executable,
            str(SKILLS_ROOT / "cometapi-image-gen" / "scripts" / "generate_image.py"),
            "--model",
            "gpt-image-1.5",
            "--size",
            "1024x1024",
            "A minimal badge icon of a comet with blue and silver tones",
            str(openai_output),
        ],
        expected_paths=[openai_output],
    )
    report["tests"].append(test_result)
    results_by_name[test_result["name"]] = test_result

    nano_output_base = run_root / "cometapi-nano-banana-edit.png"
    nano_expected = [
        run_root / "cometapi-nano-banana-edit-01.png",
        run_root / "cometapi-nano-banana-edit-02.png",
    ]
    if should_skip(["cometapi-image-gen-gpt-image"], results_by_name):
        test_result = skipped_case(
            name="cometapi-nano-banana-edit-batch",
            depends_on=["cometapi-image-gen-gpt-image"],
            reason="Dependency failed",
            expected_paths=nano_expected,
        )
    else:
        test_result = run_case(
            name="cometapi-nano-banana-edit-batch",
            command=[
                sys.executable,
                str(
                    SKILLS_ROOT
                    / "cometapi-nano-banana"
                    / "scripts"
                    / "generate_image.py"
                ),
                "--mode",
                "edit",
                "--prompt",
                "Turn this icon into a polished launch badge with a subtle glow while preserving the comet shape.",
                "--input-image",
                str(openai_output),
                "--preserve-note",
                "Keep the comet silhouette recognizable",
                "--style-note",
                "Flat product icon with crisp edges",
                "--count",
                "2",
                "--parallel",
                "2",
                "--resolution",
                "1K",
                "--output",
                str(nano_output_base),
            ],
            expected_paths=nano_expected,
            depends_on=["cometapi-image-gen-gpt-image"],
        )
    report["tests"].append(test_result)
    results_by_name[test_result["name"]] = test_result

    infographic_output = run_root / "cometapi-infographics.png"
    test_result = run_case(
        name="cometapi-infographics",
        command=[
            sys.executable,
            str(
                SKILLS_ROOT
                / "cometapi-infographics"
                / "scripts"
                / "generate_infographic.py"
            ),
            "Three simple facts about comets",
            "--type",
            "list",
            "--style",
            "technology",
            "--palette",
            "wong",
            "--image-size",
            "1K",
            "--fact",
            "Comets are icy bodies that orbit the Sun.",
            "--fact",
            "When near the Sun, comets can form a glowing coma and tail.",
            "--fact",
            "Short-period comets often originate in the Kuiper Belt.",
            "--output",
            str(infographic_output),
        ],
        expected_paths=[infographic_output],
    )
    report["tests"].append(test_result)
    results_by_name[test_result["name"]] = test_result

    report_path = run_root / "report.json"
    report["summary"] = build_summary(report["tests"])
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(f"Smoke report: {report_path}")
    print(json.dumps(report["summary"], ensure_ascii=False))
    return 0 if report["summary"]["failed"] == 0 else 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run end-to-end smoke tests for committed CometAPI skills."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / ".tmp" / "skill-smoke-tests",
        help="Directory to store smoke-test runs and reports.",
    )
    return parser.parse_args()


def run_case(
    name: str,
    command: list[str],
    expected_paths: list[Path],
    depends_on: list[str] | None = None,
) -> dict[str, Any]:
    started_at = time.time()
    proc = subprocess.run(command, capture_output=True, text=True)
    duration_seconds = round(time.time() - started_at, 2)

    outputs = []
    for path in expected_paths:
        if path.exists():
            raw = path.read_bytes()
            outputs.append(
                {
                    "path": str(path),
                    "exists": True,
                    "size_bytes": len(raw),
                    "sha256": hashlib.sha256(raw).hexdigest(),
                }
            )
        else:
            outputs.append(
                {
                    "path": str(path),
                    "exists": False,
                    "size_bytes": 0,
                    "sha256": None,
                }
            )

    success = proc.returncode == 0 and all(
        item["exists"] and item["size_bytes"] > 0 for item in outputs
    )
    return {
        "name": name,
        "depends_on": depends_on or [],
        "command": command,
        "returncode": proc.returncode,
        "duration_seconds": duration_seconds,
        "stdout": proc.stdout[-4000:],
        "stderr": proc.stderr[-4000:],
        "outputs": outputs,
        "success": success,
    }


def skipped_case(
    name: str, depends_on: list[str], reason: str, expected_paths: list[Path]
) -> dict[str, Any]:
    return {
        "name": name,
        "depends_on": depends_on,
        "command": [],
        "returncode": None,
        "duration_seconds": 0,
        "stdout": "",
        "stderr": reason,
        "outputs": [
            {
                "path": str(path),
                "exists": False,
                "size_bytes": 0,
                "sha256": None,
            }
            for path in expected_paths
        ],
        "success": False,
        "skipped": True,
    }


def should_skip(
    depends_on: list[str], results_by_name: dict[str, dict[str, Any]]
) -> bool:
    return any(
        not results_by_name.get(name, {}).get("success", False) for name in depends_on
    )


def build_summary(tests: list[dict[str, Any]]) -> dict[str, int]:
    passed = sum(1 for item in tests if item["success"])
    failed = len(tests) - passed
    return {
        "total": len(tests),
        "passed": passed,
        "failed": failed,
    }


if __name__ == "__main__":
    raise SystemExit(main())
