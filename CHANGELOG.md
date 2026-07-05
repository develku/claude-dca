# Changelog

All notable changes to this plugin are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] — unreleased

Initial public release.

### Added
- `debate-critique-agreement` skill — the full DCA protocol (independent-first
  commit → verified cross-model Codex critique → per-item convergence →
  auditable artifact).
- `dca-gate` PreToolUse hook — reminds (advisory, default) or blocks
  (`DCA_ENFORCE=1`) when a watched process-critical path is edited without a
  fresh decision artifact.
- `/codebate` slash command — kick off a decision process directly.
- `scripts/dca-codex.py` — runs the cross-model critique with active liveness
  monitoring: it polls the codex `--json` event stream and bails fast on a stall
  (default 90s of silence) instead of blocking on the full hard cap, and kills the
  codex process group on bail. Returns a JSON status (`ok`/`stalled`/`timeout`/
  `error`/`missing`) so the caller checks first rather than waiting blindly.
- `assets/TEMPLATE.md` — the artifact template the protocol fills in.
- Configurable cross-model backend model via the Codex CLI (`~/.codex/config.toml`
  or `codex exec -m <model>`), documented in the README.
