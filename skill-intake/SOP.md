# Skill Intake SOP

This SOP defines how CometAPI should discover, validate, and convert third-party skills at scale without lowering quality.

The target use case is a large intake program, such as sourcing the top 100 skills from GitHub and repeatedly narrowing them down to a smaller set of reliable, high-fit CometAPI-ready conversions.

## Stage 0: Guardrails

Before a run starts:

1. All transient artifacts must go to `.tmp/skill-intake/`.
2. The pipeline must record search queries, timestamps, repository URLs, clone commits, and evidence snippets.
3. No candidate may be marked verified from memory, intuition, or list mentions alone.

## Stage 1: Discovery

Goal: build a top-down source pool from GitHub.

Mandatory rules:

1. Search multiple query families, not one keyword only.
2. Deduplicate by `full_name`.
3. Preserve which query discovered each repository.
4. Rank by objective signals such as stars plus query coverage.

Minimum evidence saved:

- repository full name
- stars
- GitHub URL
- description
- matched queries
- default branch

Fail conditions:

- repository does not exist anymore
- repository is archived and the run excludes archived projects

## Stage 2: Materialization

Goal: convert discovered candidates into local evidence.

Mandatory rules:

1. Clone repositories locally into `.tmp/skill-intake/materialized/repos/`.
2. Record the checked-out commit SHA.
3. Never promote a repository that was not cloned locally.

Why this exists:

- README pages are not enough.
- curated lists often point to stale or renamed paths.
- local clones allow deterministic file scanning and later re-validation.

## Stage 3: Structural Validation

Goal: prove there is a real skill to inspect.

Mandatory pass criteria:

1. A real `SKILL.md` file exists.
2. The skill folder is not just a list entry or a placeholder.
3. The skill has at least one of:
   - frontmatter metadata
   - explicit usage instructions
   - helper scripts or supporting resources

Recorded evidence:

- local skill path
- parsed or extracted `name`
- parsed or extracted `description`
- companion files next to the skill

## Stage 4: Conversion Validation

Goal: determine whether the skill can actually be re-routed to CometAPI.

Mandatory rules:

1. Provider detection must come from concrete file evidence, not assumptions.
2. The pipeline must tie each provider match to a CometAPI conversion strategy.
3. The strategy must cite workspace evidence from this repository, such as `example/` or `docs/`.

Allowed conversion outcomes:

- `direct-openai-compat`
- `direct-gemini-native`
- `direct-anthropic-proxy`
- `direct-replicate-proxy`
- `provider-specific-http`
- `manual-research-required`
- `not-a-cometapi-fit`

Examples of acceptable proof:

- the source skill uses OpenAI Images and this repository already has `/v1/images/generations` examples,
- the source skill uses Gemini image generation and this repository already has native Gemini image examples,
- the source skill uses Replicate-style prediction APIs and this repository already has matching CometAPI proxy examples.

## Stage 5: User-Fit Validation

Goal: keep only skills that are genuinely useful for CometAPI users.

Mandatory checks:

1. The skill serves a modality or workflow relevant to CometAPI customers.
2. The skill is portable enough to be adapted beyond one narrow host.
3. The skill is not merely host cosmetics or a local-only code recipe with no CometAPI leverage.

High-priority categories:

- text generation
- image generation
- video generation
- music and audio generation
- multimodal workflows
- agent workflows that need model/provider swapping through CometAPI

Common rejection reasons:

- local-only art/code skill with no external AI provider
- UI decoration only
- tightly coupled to one proprietary host with no reusable logic

## Stage 6: Security and Reliability Validation

Goal: filter out risky or low-trust candidates.

Critical blockers:

- hidden shell piping such as `curl ... | sh`
- PowerShell `iex` style execution inside the skill
- destructive filesystem patterns without clear scoping
- obfuscated payloads or opaque remote execution

Non-blocking but important warnings:

- no companion scripts
- sparse metadata
- poor portability
- low evidence density

## Stage 7: Multi-Round Promotion Gate

Promotion requires all mandatory rounds to pass.

### Round A: Structural Proof

- real repo cloned locally
- real `SKILL.md`
- concrete local path recorded

### Round B: Provider Proof

- provider or workflow evidence found in files
- evidence mapped to one CometAPI strategy
- workspace citation recorded

### Round C: Product Fit Proof

- skill is relevant to CometAPI users
- not merely a list artifact or host-specific trivia

### Round D: Risk Proof

- no critical security blockers
- no major traceability gaps

Decision outcomes:

- `auto_promote`: all mandatory rounds pass and the score is high enough
- `manual_review`: structurally real but not yet strong enough for committed promotion
- `reject`: fails one or more mandatory gates

Additional constraint for `auto_promote`:

- only `image`, `video`, `text`, and `multimodal` skills may be auto-promoted
- categories such as `audio`, `music`, `automation`, or ambiguous workflows require at least manual review

## What May Enter Git

The only items that may enter the committed repository as verified candidates are those in `registry/verified_candidates.json` that passed:

- local clone proof
- conversion proof
- user-fit proof
- risk proof

Everything else stays in `.tmp/` until another validation pass upgrades it.

For traceability, every promotion run should also leave a batch snapshot in `.tmp/skill-intake/batches/` with the manifest, analyzed skills, candidates, and promotion outputs for that exact batch.

## Recommended Cadence for Top 100 Intake

1. Discover top 100 repositories.
2. Materialize top 25 by score.
3. Analyze all local `SKILL.md` files.
4. Promote only the top subset that pass all mandatory rounds.
5. Repeat with the next 25 until the target catalog is reached.

Recommended batch commands:

- batch 1: `materialize --offset 0 --top 25`
- batch 2: `materialize --offset 25 --top 25`
- batch 3: `materialize --offset 50 --top 25`
- batch 4: `materialize --offset 75 --top 25`

This keeps the process evidence-driven instead of bulk-importing noisy or low-value skills.