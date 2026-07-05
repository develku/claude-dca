---
name: debate-critique-agreement
description: Multi-model debate-critique-agreement process for high-stakes decisions. Use BEFORE any change to CLAUDE.md, settings.json, hook configs, or other files that shape how the agent behaves. Also use at design forks (Option A/B/C), before risky or irreversible changes (autonomous loops, kill switches, data/capital paths, security-sensitive code), when stuck with the root cause unclear, or when you need a second model's read of whether the evidence is complete. Runs a genuine cross-model critique via a direct `codex exec` shell-out and produces an auditable artifact. Triggers — "design fork", "architectural decision", "high-stakes", "before risky commit", "should we use A or B", "CLAUDE.md change", "edit settings.json hooks".
---

# Debate-Critique-Agreement (DCA)

A single model reviewing its own reasoning shares its own blind spots — it tends
to rubber-stamp. DCA forces a structured, auditable decision process where an
**independent cross-model critic** (Codex / GPT via the `codex` CLI) challenges
your position *after you have committed it in writing*, you respond to each point
individually, and the whole exchange is captured in one artifact file.

The artifact is the deterministic output. A companion hook (`dca-gate.sh`)
watches process-critical paths and reminds you (or blocks, in enforce mode) when
one is edited without a fresh artifact.

## When to invoke (PROACTIVELY)

Invoke this skill — without waiting to be asked — when ANY of these fire:

1. **Process-critical change** — an edit to `CLAUDE.md`, `settings.json`,
   `.claude/hooks/*`, or `.claude/skills/*`. These change how the agent behaves
   on every future turn.
2. **Design fork** — an Option A / B / C choice, or interpreting a returned verdict.
3. **Risky or irreversible change** — autonomous loops, kill switches, data or
   money paths, destructive operations, security-sensitive code.
4. **Stuck** — root cause unclear after a real effort; you want a second read.
5. **Evidence gate** — local tests passing isn't enough; you need another model's
   judgement of whether the evidence is actually complete.

## Requirements

- **Codex CLI** (`codex`) installed and authenticated — this provides the
  cross-model critic. Without it, the Codex leg is recorded as SKIPPED (the
  protocol still runs single-model, at lower confidence). See the README for
  install + how to change which model the critic uses.
- **python3** — used by the hook to parse tool input (present by default on macOS).

## Workflow

### Step 1 — Create the artifact (FIRST, always)

```bash
ts=$(date +%Y%m%dT%H%M%S)
topic="kebab-case-topic"
dir="${DCA_ARTIFACT_DIR:-$HOME/.claude/dca}"
mkdir -p "$dir"
cp "${CLAUDE_PLUGIN_ROOT}/assets/TEMPLATE.md" "$dir/${ts}_${topic}.md"
```

Open the artifact and fill the **Question + Position** and the **Evidence Pack**
before going further.

**Evidence Pack** — the shared case file BOTH legs reason from. It holds FACTS
and QUESTIONS, never a preferred answer. Split it:

- **Raw facts** — file paths + exact excerpts, code, constraints, the concrete
  question(s). Neutral; no interpretation.
- **Provided context** — prior decisions, conventions, constraints. These are
  interpretive, so label them as such with provenance (exact source + excerpt).
  Unlabeled interpretation fed as "neutral fact" silently pre-anchors both legs.

### Step 2 — Independent-first commit (your position, pre-Codex)

Before invoking Codex, write your full position into the artifact's
`## Your position (pre-Codex)` section and save. This commits your view
immutably before the critic sees anything.

The Codex prompt must include the **Evidence Pack**, the question, and the
options — but NEVER your position or which way you lean. Sharing the *case file*
ends the critic's blank-slate guessing; withholding your *opinion* preserves
independence. Shared facts ≠ shared opinion.

### Step 3 — Codex leg (genuine cross-model)

Dispatch via a **direct `codex exec` shell-out** — this is what makes the critique
genuinely cross-model and provider-verifiable. Do NOT route it through a
same-model agent wrapper: a critic that shares your model shares your blind spots
and defeats the whole purpose.

`codex exec` has no `--timeout` flag and can hang silently. Do NOT block on one
long timeout waiting to see if it ever answers. Use the shipped helper, which
launches codex, polls the event stream for liveness, and bails FAST when the
stream stalls — so you *check first* instead of waiting blindly. Write the Codex
prompt to a file, then:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/dca-codex.py" /tmp/dca_codex_prompt.txt \
  --outdir /tmp --stall 150 --hard 300
```

Branch on the exit code:

- **exit 0** — completed. The final message is on stdout (also at
  `<outdir>/dca_codex_last.txt`; the event stream at `<outdir>/dca_codex_events.jsonl`).
- **exit 124** — stalled or hit the hard cap. The helper already killed the codex
  process group. Go straight to the SKIPPED branch — no blind retry.
- **exit 127** — codex CLI not found. Go to the SKIPPED branch.

Every run prints a one-line JSON status to stderr —
`{"status": ok|stalled|timeout|error|missing, "thread_id": ..., "seconds": N}`.
Record `thread_id` as the provenance handle; put the status/reason in the SKIPPED
note when it did not complete.

Tuning: `--stall` (default 150s) is how long the event stream may go silent before
the helper declares codex hung — kept conservative because `--json` events are
milestones, not heartbeats, so a short window can kill a productive-but-silent
(high-reasoning) turn. `--hard` (default 300s) is the absolute cap. `-s read-only` =
no writes; `--json` gives the event stream whose `thread.started` event carries the
`thread_id`.

**No resume recovery:** on exit 124 this helper records SKIPPED and you re-run; it
does NOT attempt a `codex exec resume` to salvage a near-complete leg. That is a
deliberate simplification for this plugin — a genuinely useful tradeoff to be aware
of if a leg dies close to completion.

The Codex prompt MUST contain the Evidence Pack + question + options + "critique
each substantive claim (AGREE / DISAGREE / REFINE), give an overall verdict and
the biggest risk". It MUST NOT contain your pre-Codex position.

Paste the `-o` output **verbatim** into `## Codex` with the model id + `thread_id`.
Verbatim preservation stops you from reshaping the critique into something easier
to accept.

**If Codex is unavailable / times out / errors**, record:

```
SKIPPED — reason: <one sentence>
```

Explicit SKIPPED is the audit trail. Never skip silently.

### Step 4 — Respond per-item

In `## Opus`, respond to **each** critique point individually:

- **ACCEPT** — the point is correct; your position changes accordingly.
- **REFINE** — partially correct; state the modified position.
- **REBUT-WITH-EVIDENCE** — incorrect, because `<file:line>` / concrete evidence.
  Cite it. Using REBUT requires a 2nd round: re-invoke Codex with your rebuttal so
  it sees the evidence, otherwise the rebuttal is an unreviewed escape hatch.

Each disposition carries a grounding tag `[grounding: <source> → inference: …]`.
The point is the cognitive act of checking before disposing — verify the cited
text actually supports the claim. `none-found` is allowed and is a red flag to
surface, never to hide.

### Step 5 — Convergence

Run the consistency pass (same question both legs, citations verified not
assumed, verdict consistent with the per-item dispositions, no laundered
disagreement), then write ONE verdict:

| Verdict | Meaning |
|---|---|
| `AGREE` | Both legs converge cleanly; no concessions needed. |
| `REFINED-AND-PROCEED` | The critique produced concessions; the refined position is the synthesis. |
| `PARTIAL` | Agree on the core, differ on a subordinate point. Document the delta. |
| `DISAGREE` | Legs diverge with evidence; iterate a 2nd round OR escalate to the human. |
| `CODEX-SKIPPED` | Only your leg present; lower confidence; flag it. |

Include a concessions block, a no-concession declaration, or a per-leg findings
enumeration (see the template).

### Step 6 — Make the edit

With the artifact saved, the hook allows your edit once it passes the completeness
check: the 4 headers (`## Question`, `## Codex`, `## Opus`, `## Convergence`), no
remaining `DCA-FILL-ME` sentinel, and a concession/no-concession/per-leg block.

## Changing the critique model

The Codex leg runs whatever model your Codex CLI is configured with, so the
critic is swappable without touching this skill:

```toml
# ~/.codex/config.toml
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
```

Or per-invocation: `codex exec -m <model> ...` (or `-c 'model="<model>"'`).

## What the critic can and cannot see (independence notes)

The critique leg runs under `codex exec -s read-only`. Verified behaviour:

- **Filesystem = the launch directory ("workspace root").** It can read files
  under the directory you run DCA from, but not your whole home. If you launch DCA
  from inside a config repo, the critic CAN read those files — so don't rely on
  isolation. **Feed it a self-contained Evidence Pack** and treat its blindness to
  your position as a discipline, not a sandbox guarantee.
- **MCP servers are not auto-loaded.** Configured MCP servers are discoverable but
  not in the active tool set unless the critic deliberately loads them — so it
  won't silently pull from a memory store and re-anchor on your prior conclusions.
- **Web access may be ON.** `codex exec` can perform web searches (good for
  fact-checking; note it is non-deterministic and outside any Claude-side web
  guard). Disable Codex networking if you need a hermetic critique.
- **Read-only protects integrity, not independence.** It blocks writes; it does
  not stop the critic from reading your position if you leave it where it can be
  read. That is exactly why the Evidence Pack is self-contained.

## Enforcement modes

- **Advisory (default)** — the hook emits a reminder and allows the edit. It only
  reminds and logs; it does NOT block or enforce.
- **Enforce** — set `DCA_ENFORCE=1` and the hook blocks (exit 2) a watched-path
  edit that has no fresh artifact / bypass marker.
- **Quiet** — set `DCA_QUIET=1` to suppress the advisory reminder while keeping the
  audit log (ignored under `DCA_ENFORCE=1`, where a block must explain itself).

## Bypass (NOT for process-critical)

For a non-process-critical edit to a watched file, add ONE line to the new content:

```
DCA-bypass: trivial — <reason>      # diff <=20 lines, no hook/matcher config
DCA-bypass: substantive — <reason>  # general edits; logged to _bypass_log.md
```

An edit whose content touches hook-configuration keys (`"hooks"`, `"PreToolUse"`,
`"PostToolUse"`, `"matcher"`) never accepts a bypass — it needs a full artifact.

## Limits — salience and auditability, NOT prevention

The grounding tags and consistency pass are prompt discipline, not gate-enforced.
They make a skipped check *auditable* after the fact (a grounding tag whose cited
source doesn't support the claim is visible to any later reader), but nothing
mechanical forces the check — the protocol asks a possibly-lazy synthesis agent to
police its own laziness. For a decision where prevention truly matters, add an
external verifier (a cheap agent that opens each cited `file:line` and confirms
support). The hook itself is a **forgetfulness guard**, not a security parser: a
deliberately adversarial write (variable-expanded paths, `eval`, subshells,
base64 payloads) can bypass it by design.
