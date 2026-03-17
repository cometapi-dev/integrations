# CometAPI Skill Intake Pipeline

This directory contains the operating procedure and automation used to discover, validate, and promote third-party skills into the CometAPI integrations repository.

The goal is not to bulk-copy skills. The goal is to build a traceable funnel that can search the GitHub ecosystem, gather evidence, test convertibility to CometAPI, and only then allow a candidate into the committed registry.

## Principles

- No hallucinated provenance. Every candidate must point to a real repository, a real `SKILL.md`, and a real local clone in `.tmp/` during validation.
- No README-only promotion. Mentions in curated lists are useful for discovery, but they are not enough for admission.
- No silent conversion claims. Every claimed CometAPI conversion path must be backed by workspace evidence from `docs/`, `example/`, or other checked-in CometAPI references.
- No direct promotion from one signal. Promotion requires multiple validation rounds from different angles.

## Runtime Location

All runtime artifacts are written to:

```text
.tmp/skill-intake/
```

Typical outputs:

```text
.tmp/skill-intake/
├── discovery/
│   └── repositories.json
├── materialized/
│   ├── manifest.json
│   └── repos/
├── analysis/
│   ├── skills.json
│   └── candidates.json
└── promotion/
    ├── auto_promote.json
    ├── manual_review.json
    └── rejected.json
```

Each promoted run also writes a batch snapshot under:

```text
.tmp/skill-intake/batches/offset-XXXX-top-XXXX/
```

## What Is Committed

Committed files in this directory are only:

- The SOP.
- Static query/provider config.
- The automation scripts.
- The approved registry.
- Review notes and manual triage documents.

Transient discovery and clone outputs stay in `.tmp/` and do not enter git history.

## Standard Runbook

Discover the top 100 repositories:

```bash
python3 skill-intake/scripts/pipeline.py discover --top 100
```

Clone a validation batch locally:

```bash
python3 skill-intake/scripts/pipeline.py materialize --top 25
```

Clone the next batch from the discovered queue:

```bash
python3 skill-intake/scripts/pipeline.py materialize --offset 25 --top 25
```

Analyze all cloned skills:

```bash
python3 skill-intake/scripts/pipeline.py analyze
```

Apply the promotion gate:

```bash
python3 skill-intake/scripts/pipeline.py promote
```

Run the full pipeline in one command:

```bash
python3 skill-intake/scripts/pipeline.py full --top 100 --clone-limit 25 --offset 0
```

Smoke test the currently committed CometAPI skills against the live API:

```bash
python3 skill-intake/scripts/smoke_test_committed_skills.py
```

The smoke-test outputs and JSON report are written under:

```text
.tmp/skill-smoke-tests/
```

## Admission Rule

Nothing should be copied into `skills/` or added to `registry/verified_candidates.json` unless the candidate:

- exists locally in `.tmp/` as a cloned repository,
- contains an actual `SKILL.md`,
- has concrete provider or workflow evidence,
- maps to a verified CometAPI route or a clearly documented manual conversion path,
- passes all mandatory validation rounds in [`SOP.md`](SOP.md).

Direct automatic promotion is intentionally limited to `image`, `video`, `text`, and `multimodal` skills. Other categories can still land in manual review, but they do not auto-enter the short list.