---
name: cometapi-agent-designer
description: |
  Design multi-agent system architectures through CometAPI. Use this whenever the user
  mentions multi-agent design, agent orchestration, agent architecture planning,
  coordination patterns (supervisor, swarm, hierarchical, pipeline), defining agent
  roles, mapping tool interfaces, or generating implementation roadmaps. Also trigger
  when the user wants a Mermaid diagram of an agent workflow, asks "how should I
  structure my agents", or needs to decide between single-agent vs multi-agent approaches.
  If the conversation involves planning agent responsibilities, guardrails, or rollout
  strategies, this skill applies.
compatibility:
  requires:
    - Python 3
    - COMETAPI_KEY environment variable
---

# CometAPI Agent Designer

This skill generates multi-agent architecture briefs using CometAPI's text models.
Give it a goal, a list of tasks, and constraints — it produces a Markdown architecture
document with agent roles, coordination patterns, guardrails, and a Mermaid diagram
you can paste into planning docs.

The helper calls `gpt-4.1-mini` via CometAPI's `/v1/chat/completions` endpoint. It
uses a text model (not an image model) because the output is structured reasoning,
not a visual asset.

## Why This Skill Exists

Designing multi-agent systems is a common planning task where the user benefits from
structured guidance — choosing between coordination patterns, sizing the team, defining
guardrails. The helper encodes best practices from real agent system design so the
user gets a concrete starting point rather than a vague brainstorm.

## What It Produces

1. **Architecture brief** (Markdown) — overview, agent roles, coordination pattern,
   tool interfaces, guardrails, and a phased rollout plan.
2. **Mermaid diagram** (`.mmd` file) — extracted automatically when the model includes
   a Mermaid code block. Ready to paste into GitHub, Notion, or any Mermaid renderer.
3. **Sidecar metadata** (JSON) — model used, prompt inputs, output paths, timestamp.

## Usage Examples

**Example 1 — Design a support system:**
```bash
python scripts/design_agent_system.py \
  --goal "Design a multi-agent support system for CometAPI" \
  --task "Route incoming requests to the right specialist" \
  --task "Escalate risky or billing-sensitive requests to a human" \
  --integration "CometAPI text models" \
  --integration "CometAPI image generation skills" \
  --constraint "Keep the operating team small" \
  --team-size 3 \
  --output agent-architecture.md
```
Output: `agent-architecture.md` + `agent-architecture.mmd` + sidecar JSON.

**Example 2 — Compare patterns for a data pipeline:**
```bash
python scripts/design_agent_system.py \
  --goal "Build an agent pipeline that ingests, validates, and transforms data" \
  --task "Ingest from S3 and Kafka" \
  --task "Validate schema and data quality" \
  --task "Transform and load into the warehouse" \
  --pattern pipeline \
  --output data-agents.md
```

## Configuration

| Flag | Purpose | Default |
|------|---------|--------|
| `--goal` | High-level system objective | (required) |
| `--task` | Specific task the system handles (repeatable) | none |
| `--integration` | External system or API the agents use (repeatable) | none |
| `--constraint` | Design constraint (repeatable) | none |
| `--team-size` | Target number of agents | 3 |
| `--pattern` | Preferred coordination pattern | auto-selected |
| `--output` | Output Markdown path | Timestamped filename |

## Constraints

- This skill is for architecture **planning**, not implementation. If the user already
  has a design and wants working code, treat that as a follow-on coding task.
- The designs intentionally treat CometAPI as the model-routing layer rather than
  hardcoding a specific upstream provider — this is by design, since CometAPI users
  benefit from being able to swap models without changing agent logic.
- For image generation tasks, use the Nano Banana family or `cometapi-image-gen` instead.