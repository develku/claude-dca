# DCA Artifact — <topic>

**Timestamp:** <DCA-FILL-ME — YYYY-MM-DDTHH:MM:SS+TZ>
**Driver session:** <DCA-FILL-ME — project path + branch>
**Trigger:** <DCA-FILL-ME — which trigger fired (process-critical edit, design fork, risky change, stuck, evidence gate)>

> NOTE: This file contains `<DCA-FILL-ME — ...>` sentinels. The hook gate
> REJECTS any artifact still containing this string. Replace EVERY sentinel
> with real content (or delete the sentinel line) before the artifact is
> accepted as a valid DCA decision record.

---

## Mode declaration

Check one (the gate does NOT validate this; audit mismatches yourself later):

- [ ] **BIDIRECTIONAL DEBATE** — both legs commit positions independently, exchange, respond per-item, document concessions. Required for any artifact that backs an implementation/process/architecture decision.
- [ ] **CONSULT-ONLY** — you need a single cross-model verification; the result will NOT back a decision. If a CONSULT-ONLY artifact ends up cited as decision-provenance, it is retroactively invalid; convert to BIDIRECTIONAL DEBATE and re-run.

---

## Question + Position

<DCA-FILL-ME — What is being decided? State the question concretely.>

**Options on the table:**
- A) ...
- B) ...
- C) ...

**Files that will change if this proceeds:**
- ...

---

## Evidence Pack

> The shared case file BOTH legs reason from (the Codex prompt includes this; it
> does NOT include your own position below). Facts and questions only — never a
> preferred answer. See the skill's Step 1.

**Raw facts** (neutral — paths + exact excerpts, code, constraints):
- <DCA-FILL-ME — file:line excerpts, constraints, the concrete question(s)>

**Provided context** (interpretive — label as constraints, with provenance):
- <DCA-FILL-ME — prior decision / convention; cite exact source; note "selected by driver, not an exhaustive search"; or "none">

---

## Your position (pre-Codex)

> Write this BEFORE invoking Codex. The Codex prompt must NOT contain this text.
> Saving this section first commits your view immutably and prevents the
> reaction-only failure mode (reshaping your view to match the critic).

**Position:** <DCA-FILL-ME — your recommendation, before any cross-model input>

**Trade-offs weighed:**
- ...

**What I'd be wrong about if X breaks:** <state the load-bearing assumption>

---

## Codex

**Invocation:** `codex exec -s read-only --json -o <last> < <prompt>`
**Model:** <DCA-FILL-ME — from ~/.codex/config.toml, e.g. gpt-5.5>
**thread_id:** <DCA-FILL-ME — from the JSON event stream (thread.started)>
**Verdict:** AGREE / DISAGREE / PARTIAL / REFINE

**Verbatim critique** (block-quote or fenced — do NOT paraphrase):

> <DCA-FILL-ME — paste the critic's response verbatim>

<OR, if skipped:>

**SKIPPED — reason:** <one sentence, e.g. "codex CLI not installed", "codex exec timed out">

---

## Opus

> Per-item response to each critique point. Each gets one disposition:
> ACCEPT / REFINE / REBUT-WITH-EVIDENCE (the last requires a 2nd round).
> Every disposition carries a claim→citation→inference grounding tag — verify the
> cited text supports the claim before disposing.

### Re <critique point 1> — ACCEPT / REFINE / REBUT-WITH-EVIDENCE

<your response> **[grounding: <source> | code:<file:line> | none-found] → inference: …**

### Re <critique point 2> — ...

...

---

## Convergence

**Verdict:** AGREE / REFINED-AND-PROCEED / PARTIAL / DISAGREE / CODEX-SKIPPED

**Consistency pass:** same question both legs · same evidence base (citations
verified, not assumed) · verdict ↔ per-item dispositions non-contradictory · no
unsupported citation · no laundered disagreement (a REBUT quietly downgraded to
ACCEPT without evidence). **Unsupported claims / unresolved disagreements:** <list or "none">

Convergence MUST contain ONE of (a), (b), or (c):

**(a) Concessions block** — for any artifact where a critique exchange happened:

- **Codex-conceded points:** <list, or "none in this round">
- **Opus-conceded points:** <list, or "none in this round">
- **Unresolved disagreements:** <list, or "none — proceed">

**(b) No-concession declaration** — for clean AGREE artifacts only:

**No concessions — both legs converged independently because:** <reason>

**(c) Per-leg findings enumeration** — for parallel-discovery cases:

**Cross-perspective overlap (both agents independently arrived at):**
- ...

**Non-overlap (each surfaced something the other didn't):**
- Codex unique: ...
- Opus unique: ...

---

**Iteration log (if any REBUT-WITH-EVIDENCE was used):**
- Round 1 deltas: ...
- Round 2 outcome (critic re-shown the rebuttal): ...
- Final: <convergence or escalation>

---

## Action taken

**Files changed:** <list>
**DCA-bypass markers used (if any):** <list>
