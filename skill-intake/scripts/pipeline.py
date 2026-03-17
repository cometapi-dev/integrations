#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from urllib import error, parse, request


REPO_ROOT = Path(__file__).resolve().parents[2]
INTAKE_ROOT = REPO_ROOT / "skill-intake"
CONFIG_ROOT = INTAKE_ROOT / "config"
REGISTRY_ROOT = INTAKE_ROOT / "registry"
TMP_ROOT = REPO_ROOT / ".tmp" / "skill-intake"
BATCH_ROOT = TMP_ROOT / "batches"

DISCOVERY_FILE = TMP_ROOT / "discovery" / "repositories.json"
MATERIALIZED_FILE = TMP_ROOT / "materialized" / "manifest.json"
SKILLS_FILE = TMP_ROOT / "analysis" / "skills.json"
CANDIDATES_FILE = TMP_ROOT / "analysis" / "candidates.json"

SECURITY_PATTERNS = {
    "curl-pipe-shell": r"curl[^\n|]*\|\s*(sh|bash|zsh)",
    "wget-pipe-shell": r"wget[^\n|]*\|\s*(sh|bash|zsh)",
    "powershell-iex": r"\biex\b|\birm\b",
    "dangerous-rm": r"rm\s+-rf\s+(/|~|\$HOME)",
    "eval-base64": r"eval\s*\(|base64\s+--decode",
}

MODALITY_RULES = {
    "image": ["image", "illustration", "icon", "poster", "art", "render", "logo"],
    "video": ["video", "remotion", "animation", "gif", "text2video"],
    "audio": ["audio", "speech", "tts", "transcribe", "voice"],
    "music": ["music", "suno", "song", "melody"],
    "text": ["text", "chat", "claude", "openai", "copywriting", "writing"],
    "multimodal": ["multimodal", "vision", "image+text", "image to text"],
    "automation": ["automation", "workflow", "github", "slack", "notion", "gmail"],
}

HIGH_FIT_MODALITIES = {"image", "video", "audio", "music", "text", "multimodal"}
AUTO_PROMOTE_MODALITIES = {"image", "video", "text", "multimodal"}
PORTABLE_HOST_MARKERS = {
    ".claude",
    ".github",
    ".cursor",
    ".gemini",
    ".agent",
    ".agents",
}


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        if args.command == "discover":
            repositories = discover(top=args.top)
            print(f"Discovered {len(repositories)} repositories -> {DISCOVERY_FILE}")
            return 0
        if args.command == "materialize":
            manifest = materialize(top=args.top, offset=args.offset)
            print(f"Materialized {len(manifest)} repositories -> {MATERIALIZED_FILE}")
            return 0
        if args.command == "analyze":
            skills, candidates = analyze()
            print(
                f"Analyzed {len(skills)} skills and produced {len(candidates)} candidates"
            )
            return 0
        if args.command == "promote":
            promotion = promote(write_registry=args.write_registry)
            print(
                "Promotion results: "
                f"auto={len(promotion['auto_promote'])}, "
                f"manual={len(promotion['manual_review'])}, "
                f"rejected={len(promotion['rejected'])}"
            )
            return 0
        if args.command == "full":
            repositories = discover(top=args.top)
            print(f"Discovered {len(repositories)} repositories")
            manifest = materialize(top=args.clone_limit, offset=args.offset)
            print(f"Materialized {len(manifest)} repositories")
            skills, candidates = analyze()
            print(
                f"Analyzed {len(skills)} skills and produced {len(candidates)} candidates"
            )
            promotion = promote(write_registry=args.write_registry)
            print(
                "Promotion results: "
                f"auto={len(promotion['auto_promote'])}, "
                f"manual={len(promotion['manual_review'])}, "
                f"rejected={len(promotion['rejected'])}"
            )
            return 0
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="CometAPI skill intake pipeline")
    subparsers = parser.add_subparsers(dest="command", required=True)

    discover_parser = subparsers.add_parser(
        "discover", help="Search GitHub for candidate repositories"
    )
    discover_parser.add_argument(
        "--top",
        type=int,
        default=100,
        help="Maximum repositories to keep after deduping",
    )

    materialize_parser = subparsers.add_parser(
        "materialize", help="Clone candidate repositories into .tmp"
    )
    materialize_parser.add_argument(
        "--top", type=int, default=25, help="How many discovered repositories to clone"
    )
    materialize_parser.add_argument(
        "--offset",
        type=int,
        default=0,
        help="Skip this many discovered repositories before cloning",
    )

    subparsers.add_parser(
        "analyze",
        help="Analyze cloned repositories for real SKILL.md files and conversion fit",
    )

    promote_parser = subparsers.add_parser(
        "promote", help="Apply the promotion gate to analyzed candidates"
    )
    promote_parser.add_argument(
        "--write-registry",
        action="store_true",
        help="Write auto-promoted candidates to the committed registry",
    )

    full_parser = subparsers.add_parser(
        "full", help="Run discover, materialize, analyze, and promote"
    )
    full_parser.add_argument(
        "--top", type=int, default=100, help="Discovery cap after deduping"
    )
    full_parser.add_argument(
        "--clone-limit",
        type=int,
        default=25,
        help="How many repositories to clone locally",
    )
    full_parser.add_argument(
        "--offset",
        type=int,
        default=0,
        help="Skip this many discovered repositories before the materialize step",
    )
    full_parser.add_argument(
        "--write-registry",
        action="store_true",
        help="Write auto-promoted candidates to the committed registry",
    )

    return parser


def discover(top: int) -> list[dict[str, Any]]:
    ensure_tmp_dirs()
    query_entries = load_json(CONFIG_ROOT / "search_queries.json")
    aggregated: dict[str, dict[str, Any]] = {}

    for entry in query_entries:
        results = github_search_repositories(
            query=entry["query"],
            per_page=min(int(entry.get("per_page", 100)), 100),
            sort=entry.get("sort", "stars"),
            order=entry.get("order", "desc"),
        )
        for item in results:
            repo = normalize_repository(item)
            existing = aggregated.get(repo["full_name"])
            if existing is None:
                repo["matched_queries"] = [entry["name"]]
                aggregated[repo["full_name"]] = repo
            else:
                if entry["name"] not in existing["matched_queries"]:
                    existing["matched_queries"].append(entry["name"])

    repositories = sorted(
        aggregated.values(),
        key=lambda item: (item["stars"], len(item["matched_queries"])),
        reverse=True,
    )[:top]

    write_json(
        DISCOVERY_FILE,
        {
            "generated_at": iso_now(),
            "top": top,
            "repositories": repositories,
        },
    )
    return repositories


def materialize(top: int, offset: int = 0) -> list[dict[str, Any]]:
    discovery = require_json(DISCOVERY_FILE)
    repositories = discovery["repositories"][offset : offset + top]
    clones_root = TMP_ROOT / "materialized" / "repos"
    manifest: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []

    for repo in repositories:
        local_path = clones_root / repo["full_name"].replace("/", "__")
        if local_path.exists():
            shutil.rmtree(local_path)
        clone_error = try_clone_repository(repo["html_url"], local_path)
        if clone_error is not None:
            failures.append(
                {
                    "full_name": repo["full_name"],
                    "html_url": repo["html_url"],
                    "error": clone_error,
                }
            )
            continue
        sha = run_command(["git", "-C", str(local_path), "rev-parse", "HEAD"]).strip()
        manifest.append(
            {
                "full_name": repo["full_name"],
                "html_url": repo["html_url"],
                "stars": repo["stars"],
                "matched_queries": repo["matched_queries"],
                "default_branch": repo["default_branch"],
                "local_path": str(local_path),
                "commit_sha": sha,
            }
        )

    write_json(
        MATERIALIZED_FILE,
        {
            "generated_at": iso_now(),
            "top": top,
            "offset": offset,
            "repositories": manifest,
            "failures": failures,
        },
    )
    return manifest


def analyze() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    ensure_tmp_dirs()
    provider_rules = load_json(CONFIG_ROOT / "provider_rules.json")
    materialized = require_json(MATERIALIZED_FILE)["repositories"]

    skills: list[dict[str, Any]] = []
    candidates: list[dict[str, Any]] = []

    for repo in materialized:
        repo_path = Path(repo["local_path"])
        skill_files = sorted(repo_path.rglob("SKILL.md"))
        for skill_file in skill_files:
            record = analyze_skill(repo, skill_file, provider_rules)
            skills.append(record)
            candidates.append(build_candidate(record))

    write_json(
        SKILLS_FILE,
        {
            "generated_at": iso_now(),
            "skills": skills,
        },
    )
    write_json(
        CANDIDATES_FILE,
        {
            "generated_at": iso_now(),
            "candidates": candidates,
        },
    )
    return skills, candidates


def promote(write_registry: bool) -> dict[str, list[dict[str, Any]]]:
    candidates = require_json(CANDIDATES_FILE)["candidates"]
    auto_promote: list[dict[str, Any]] = []
    manual_review: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []

    for candidate in candidates:
        decision = candidate["decision"]
        if decision == "auto_promote":
            auto_promote.append(candidate)
        elif decision == "manual_review":
            manual_review.append(candidate)
        else:
            rejected.append(candidate)

    promotion_root = TMP_ROOT / "promotion"
    write_json(promotion_root / "auto_promote.json", auto_promote)
    write_json(promotion_root / "manual_review.json", manual_review)
    write_json(promotion_root / "rejected.json", rejected)
    write_batch_snapshot(auto_promote, manual_review, rejected)

    if write_registry:
        write_json(REGISTRY_ROOT / "verified_candidates.json", auto_promote)
        write_json(REGISTRY_ROOT / "manual_review_candidates.json", manual_review)

    return {
        "auto_promote": auto_promote,
        "manual_review": manual_review,
        "rejected": rejected,
    }


def analyze_skill(
    repo: dict[str, Any],
    skill_file: Path,
    provider_rules: list[dict[str, Any]],
) -> dict[str, Any]:
    skill_text = safe_read_text(skill_file)
    frontmatter = extract_frontmatter(skill_text)
    companion_files = collect_companion_files(skill_file)

    evidence_pool = [(skill_file, skill_text)]
    for file_path in companion_files:
        evidence_pool.append((file_path, safe_read_text(file_path)))

    provider_matches = detect_provider_matches(evidence_pool, provider_rules)
    security_flags = detect_security_flags(evidence_pool)
    modality = detect_modality(skill_file, frontmatter, evidence_pool)
    portability = detect_portability(skill_file)

    best_provider = provider_matches[0] if provider_matches else None
    has_non_fit_match = any(
        match["conversion_strategy"] == "not-a-cometapi-fit"
        for match in provider_matches
    )
    has_strong_provider_evidence = bool(best_provider) and (
        best_provider["evidence_count"] >= 2
        or any(
            not evidence["file"].endswith("SKILL.md")
            for evidence in best_provider["evidence"]
        )
    )
    conversion_strategy = (
        best_provider["conversion_strategy"]
        if best_provider
        else "manual-research-required"
    )

    structural_pass = True
    provider_pass = (
        best_provider is not None
        and conversion_strategy
        not in {"manual-research-required", "not-a-cometapi-fit"}
        and has_strong_provider_evidence
    )
    user_fit_pass = (
        modality in HIGH_FIT_MODALITIES
        and conversion_strategy != "not-a-cometapi-fit"
        and not has_non_fit_match
    )
    risk_pass = not any(flag["severity"] == "critical" for flag in security_flags)

    return {
        "repo_full_name": repo["full_name"],
        "repo_url": repo["html_url"],
        "repo_stars": repo["stars"],
        "repo_queries": repo["matched_queries"],
        "repo_commit_sha": repo["commit_sha"],
        "skill_path": str(skill_file),
        "skill_name": frontmatter.get("name") or skill_file.parent.name,
        "skill_description": frontmatter.get("description") or "",
        "companion_files": [str(path) for path in companion_files],
        "portability": portability,
        "modality": modality,
        "provider_matches": provider_matches,
        "best_conversion_strategy": conversion_strategy,
        "has_non_fit_match": has_non_fit_match,
        "has_strong_provider_evidence": has_strong_provider_evidence,
        "validation_rounds": {
            "structural_proof": structural_pass,
            "provider_proof": provider_pass,
            "product_fit_proof": user_fit_pass,
            "risk_proof": risk_pass,
        },
        "security_flags": security_flags,
    }


def build_candidate(skill: dict[str, Any]) -> dict[str, Any]:
    stars = int(skill["repo_stars"])
    popularity_score = min(30, round(math.log10(max(stars, 1)) * 10, 2))

    strategy = skill["best_conversion_strategy"]
    if strategy.startswith("direct-"):
        convertibility_score = 30
    elif strategy == "provider-specific-http":
        convertibility_score = 24
    elif strategy == "manual-research-required":
        convertibility_score = 10
    else:
        convertibility_score = 0

    portability_score = 15 if skill["portability"] == "portable" else 8
    traceability_score = min(15, 5 + len(skill["provider_matches"]) * 5)
    user_fit_score = 10 if skill["modality"] in HIGH_FIT_MODALITIES else 2
    total_score = round(
        popularity_score
        + convertibility_score
        + portability_score
        + traceability_score
        + user_fit_score,
        2,
    )

    rounds = skill["validation_rounds"]
    if (
        all(rounds.values())
        and total_score >= 75
        and skill["has_strong_provider_evidence"]
        and not skill["has_non_fit_match"]
        and skill["modality"] in AUTO_PROMOTE_MODALITIES
        and skill["best_conversion_strategy"]
        in {
            "direct-openai-compat",
            "direct-gemini-native",
            "direct-replicate-proxy",
            "provider-specific-http",
        }
    ):
        decision = "auto_promote"
    elif (
        rounds["structural_proof"] and rounds["provider_proof"] and rounds["risk_proof"]
    ):
        decision = "manual_review"
    else:
        decision = "reject"

    return {
        "repo_full_name": skill["repo_full_name"],
        "repo_url": skill["repo_url"],
        "repo_commit_sha": skill["repo_commit_sha"],
        "skill_name": skill["skill_name"],
        "skill_path": skill["skill_path"],
        "modality": skill["modality"],
        "best_conversion_strategy": skill["best_conversion_strategy"],
        "provider_matches": skill["provider_matches"],
        "has_non_fit_match": skill["has_non_fit_match"],
        "has_strong_provider_evidence": skill["has_strong_provider_evidence"],
        "validation_rounds": skill["validation_rounds"],
        "security_flags": skill["security_flags"],
        "score": {
            "popularity": popularity_score,
            "convertibility": convertibility_score,
            "portability": portability_score,
            "traceability": traceability_score,
            "user_fit": user_fit_score,
            "total": total_score,
        },
        "decision": decision,
    }


def github_search_repositories(
    query: str, per_page: int, sort: str, order: str
) -> list[dict[str, Any]]:
    params = parse.urlencode(
        {
            "q": query,
            "sort": sort,
            "order": order,
            "per_page": per_page,
            "page": 1,
        }
    )
    url = f"https://api.github.com/search/repositories?{params}"
    payload = github_request_json(url)
    return payload.get("items", [])


def github_request_json(url: str) -> dict[str, Any]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "cometapi-skill-intake",
    }

    token = (
        os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or gh_auth_token()
    )
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = request.Request(url, headers=headers)
    try:
        with request.urlopen(req, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GitHub API request failed ({exc.code}): {raw}") from exc
    except error.URLError as exc:
        raise RuntimeError(f"GitHub API request failed: {exc.reason}") from exc


def gh_auth_token() -> str | None:
    try:
        value = run_command(["gh", "auth", "token"], check=False).strip()
        return value or None
    except RuntimeError:
        return None


def normalize_repository(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "full_name": item["full_name"],
        "html_url": item["html_url"],
        "description": item.get("description") or "",
        "stars": int(item.get("stargazers_count") or 0),
        "default_branch": item.get("default_branch") or "main",
    }


def collect_companion_files(skill_file: Path) -> list[Path]:
    parent = skill_file.parent
    candidates: list[Path] = []
    for path in sorted(parent.iterdir()):
        if path == skill_file:
            continue
        if path.is_file() and path.suffix.lower() in {
            ".py",
            ".js",
            ".ts",
            ".sh",
            ".ps1",
            ".md",
            ".json",
            ".yaml",
            ".yml",
        }:
            candidates.append(path)
        elif path.is_dir() and path.name in {
            "scripts",
            "resources",
            "templates",
            "rules",
        }:
            for nested in sorted(path.rglob("*")):
                if nested.is_file() and nested.suffix.lower() in {
                    ".py",
                    ".js",
                    ".ts",
                    ".sh",
                    ".ps1",
                    ".md",
                    ".json",
                    ".yaml",
                    ".yml",
                }:
                    candidates.append(nested)
    return candidates[:25]


def detect_provider_matches(
    evidence_pool: list[tuple[Path, str]],
    provider_rules: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    matches: list[dict[str, Any]] = []
    for rule in provider_rules:
        hit_evidence: list[dict[str, str]] = []
        for file_path, text in evidence_pool:
            lowered = text.lower()
            for token in rule["match_any"]:
                lowered_token = token.lower()
                if lowered_token in lowered:
                    hit_evidence.append(
                        {
                            "file": str(file_path),
                            "token": token,
                        }
                    )
                    break

        if hit_evidence:
            matches.append(
                {
                    "provider": rule["name"],
                    "conversion_strategy": rule["conversion_strategy"],
                    "workspace_evidence": rule.get("workspace_evidence", []),
                    "evidence": hit_evidence[:5],
                    "evidence_count": len(hit_evidence),
                }
            )

    matches.sort(key=lambda item: item["evidence_count"], reverse=True)
    return matches


def detect_security_flags(
    evidence_pool: list[tuple[Path, str]],
) -> list[dict[str, str]]:
    flags: list[dict[str, str]] = []
    for file_path, text in evidence_pool:
        for name, pattern in SECURITY_PATTERNS.items():
            if re.search(pattern, text, flags=re.IGNORECASE):
                severity = (
                    "critical"
                    if name in {"curl-pipe-shell", "wget-pipe-shell", "dangerous-rm"}
                    else "warning"
                )
                flags.append(
                    {"file": str(file_path), "rule": name, "severity": severity}
                )
    return flags


def detect_modality(
    skill_file: Path,
    frontmatter: dict[str, str],
    evidence_pool: list[tuple[Path, str]],
) -> str:
    parts = [
        skill_file.parent.name,
        frontmatter.get("name", ""),
        frontmatter.get("description", ""),
    ]
    for _, text in evidence_pool[:5]:
        parts.append(text[:4000])
    blob = "\n".join(parts).lower()

    scores: dict[str, int] = {}
    for modality, keywords in MODALITY_RULES.items():
        scores[modality] = sum(1 for keyword in keywords if keyword in blob)

    best = max(scores.items(), key=lambda item: item[1])
    return best[0] if best[1] > 0 else "other"


def detect_portability(skill_file: Path) -> str:
    path_blob = str(skill_file).lower()
    if any(marker in path_blob for marker in PORTABLE_HOST_MARKERS):
        return "portable"
    return "host-coupled"


def extract_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end == -1:
        return {}
    block = text[4:end].splitlines()
    data: dict[str, str] = {}
    current_key: str | None = None
    current_value: list[str] = []

    for raw_line in block:
        line = raw_line.rstrip()
        if not line:
            continue
        if re.match(r"^[A-Za-z0-9_-]+:\s*", line):
            if current_key is not None:
                data[current_key] = "\n".join(current_value).strip()
            key, value = line.split(":", 1)
            current_key = key.strip()
            current_value = [value.strip().lstrip("|").strip()] if value.strip() else []
        elif current_key is not None:
            current_value.append(line.strip())

    if current_key is not None:
        data[current_key] = "\n".join(current_value).strip()
    return data


def ensure_tmp_dirs() -> None:
    for path in [
        TMP_ROOT / "discovery",
        TMP_ROOT / "materialized" / "repos",
        TMP_ROOT / "analysis",
        TMP_ROOT / "promotion",
        BATCH_ROOT,
    ]:
        path.mkdir(parents=True, exist_ok=True)


def write_batch_snapshot(
    auto_promote: list[dict[str, Any]],
    manual_review: list[dict[str, Any]],
    rejected: list[dict[str, Any]],
) -> None:
    manifest = require_json(MATERIALIZED_FILE)
    offset = int(manifest.get("offset", 0))
    top = int(manifest.get("top", len(manifest.get("repositories", []))))
    batch_dir = BATCH_ROOT / f"offset-{offset:04d}-top-{top:04d}"
    batch_dir.mkdir(parents=True, exist_ok=True)

    write_json(batch_dir / "manifest.json", manifest)
    write_json(batch_dir / "skills.json", require_json(SKILLS_FILE))
    write_json(batch_dir / "candidates.json", require_json(CANDIDATES_FILE))
    write_json(batch_dir / "auto_promote.json", auto_promote)
    write_json(batch_dir / "manual_review.json", manual_review)
    write_json(batch_dir / "rejected.json", rejected)
    write_json(
        batch_dir / "summary.json",
        {
            "generated_at": iso_now(),
            "offset": offset,
            "top": top,
            "auto_promote": len(auto_promote),
            "manual_review": len(manual_review),
            "rejected": len(rejected),
        },
    )


def safe_read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def run_command(
    command: list[str], check: bool = True, env: dict[str, str] | None = None
) -> str:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    result = subprocess.run(command, capture_output=True, text=True, env=merged_env)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stderr.strip()}"
        )
    return result.stdout


def try_clone_repository(
    repo_url: str, local_path: Path, attempts: int = 3
) -> str | None:
    base_command = [
        "git",
        "clone",
        "--depth",
        "1",
        "--filter=blob:none",
        "-c",
        "filter.lfs.smudge=",
        "-c",
        "filter.lfs.process=",
        "-c",
        "filter.lfs.required=false",
        repo_url,
        str(local_path),
    ]
    last_error = ""
    for attempt in range(1, attempts + 1):
        if local_path.exists():
            shutil.rmtree(local_path)
        try:
            run_command(base_command, env={"GIT_LFS_SKIP_SMUDGE": "1"})
            return None
        except RuntimeError as exc:
            last_error = str(exc)
            if attempt < attempts:
                time.sleep(3 * attempt)
    return last_error


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def require_json(path: Path) -> Any:
    if not path.exists():
        raise RuntimeError(f"Required file does not exist: {path}")
    return load_json(path)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


if __name__ == "__main__":
    raise SystemExit(main())
