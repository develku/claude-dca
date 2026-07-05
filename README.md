# DCA — Debate-Critique-Agreement for Claude Code

> A decision gate that makes an AI argue against itself — *properly*.

When you ask a model to review its own reasoning, it rubber-stamps. It shares its
own blind spots, so "looks good to me" is nearly free. **DCA** fixes that by
forcing a structured, auditable process around your riskiest decisions:

1. **Commit your position first**, in writing, before any critique.
2. **Get a genuine cross-model critique** — a *different* model (Codex / GPT via
   the `codex` CLI) challenges each claim, having never seen your conclusion.
3. **Respond point-by-point**, citing evidence for every disposition.
4. **Converge** into one verdict, captured in an auditable artifact file.

A companion hook watches process-critical paths (`CLAUDE.md`, `settings.json`,
`.claude/hooks/*`, `.claude/skills/*`) and reminds you — or blocks you, in
enforce mode — when you edit one without doing the work.

## Why "cross-model" is the whole point

This project exists because of a bug worth telling. An earlier version routed the
"cross-model" critique through a convenient agent wrapper — and a provenance probe
found that wrapper was quietly returning the **same** model doing the driving. A
critic that shares your model shares your blind spots: the "second opinion" was an
echo. The fix was to shell out **directly** to `codex exec`, whose model is
provider-verifiable.

The lesson generalizes: the value of a critique leg is not how *capable* it is —
it's how *independent* it is. DCA is built around protecting that independence
(commit-first, self-contained evidence, verbatim critique) rather than maximizing
the critic's power.

## Install

Requires the [Codex CLI](https://github.com/openai/codex) installed and
authenticated (this is the cross-model critic) and `python3`.

```
/plugin marketplace add develku/claude-dca
/plugin install dca@develku
```

Then, at any decision fork:

```
/dca should we store sessions in Postgres or SQLite for this workload?
```

…or just describe a high-stakes change — the `debate-critique-agreement` skill
triggers proactively.

## How it works

| Piece | Role |
|---|---|
| `debate-critique-agreement` skill | The protocol: commit → cross-model critique → per-item convergence → artifact. |
| `dca-gate.sh` hook | Watches process-critical paths; reminds/blocks when one is edited with no fresh artifact. |
| `scripts/dca-codex.py` | Runs the critique with liveness monitoring — polls codex's event stream and bails fast if it hangs, instead of blocking on a long timeout. |
| `assets/TEMPLATE.md` | The artifact skeleton the protocol fills in. |
| `/dca` command | Kicks off a decision process directly. |

**Hang-resistant by design:** codex can stall without returning. Rather than
wait out a long timeout, the helper watches the event stream for liveness and
bails on a stall (killing the codex process group), reporting a clear status so
the run records a `SKIPPED` and moves on — it *checks first*. The stall window
(`--stall`, default 150s) is deliberately conservative: `--json` events are
milestones, not heartbeats, so a short window can kill a productive-but-silent
high-reasoning turn. Note it does **not** attempt a `codex exec resume` to
salvage a near-complete leg — a deliberate simplification for this plugin.

Each decision produces one artifact at `~/.claude/dca/<timestamp>_<topic>.md`
containing the question, the verbatim cross-model critique (with the model id and
`thread_id` as a provenance handle), your per-item responses, and the convergence
verdict.

## Changing the critique model

The critic runs whatever model your Codex CLI is set to — no code change needed:

```toml
# ~/.codex/config.toml
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
```

Or per-invocation: `codex exec -m <model> ...` (or `-c 'model="<model>"'`).

## What the critic can and cannot see

The leg runs under `codex exec -s read-only`. Verified behaviour:

- **Filesystem = the directory you launch from** (not your whole home). Launch DCA
  from inside a config repo and the critic *can* read those files — so don't rely
  on isolation; feed it a self-contained Evidence Pack.
- **MCP servers are not auto-loaded** — the critic won't silently read a memory
  store and re-anchor on your prior conclusions unless it deliberately loads one.
- **Web access may be on** — good for fact-checking, but non-deterministic and
  outside any Claude-side web guard. Disable Codex networking for a hermetic run.
- **Read-only protects integrity, not independence** — it blocks writes, not reads.
  Keep your committed position out of the critic's reachable path.

## Enforcement modes

| Mode | Behaviour | How |
|---|---|---|
| **Advisory** (default) | Hook prints a reminder, allows the edit. | — |
| **Enforce** | Hook blocks (exit 2) a watched-path edit with no fresh artifact. | `export DCA_ENFORCE=1` |

Advisory is the default on purpose: a hard gate that fires on every config edit
gets resented and routed around. Turn on enforcement when you *want* the friction.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DCA_ENFORCE` | `0` | `1` = hard-block instead of advisory reminder. |
| `DCA_ARTIFACT_DIR` | `~/.claude/dca` | Where decision artifacts are written. |

## Limits (read these)

DCA raises the cost of sloppy decisions; it does not make good ones automatic.

- The grounding tags and consistency checks are **prompt discipline, not
  gate-enforced** — they make a skipped check auditable, but nothing mechanical
  forces it. For decisions where prevention truly matters, add an external
  verifier that opens each cited source.
- The hook is a **forgetfulness guard, not a security parser** — a deliberately
  adversarial write (variable-expanded paths, `eval`, subshells, base64 payloads)
  bypasses it by design. Use `settings.json` `permissions.deny` for a harder stop.

## License

MIT © develku
