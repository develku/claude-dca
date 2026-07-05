#!/usr/bin/env bash
# DCA Gate — PreToolUse hook for Edit|Write|MultiEdit|Bash on watched
# process-critical paths (CLAUDE.md, settings.json, .claude/hooks/*,
# .claude/skills/*). Nudges you through the debate-critique-agreement workflow
# before you change something that shapes how the agent behaves.
#
# Companion to the `debate-critique-agreement` skill shipped in this plugin.
#
# Hook input: PreToolUse JSON on stdin with {tool_name, tool_input, ...}
# Hook output:
#   - exit 0  → allow (also used by advisory mode; message goes to stderr)
#   - exit 2  → block (stderr shown to the model) — only in DCA_ENFORCE=1
#   - other   → error
#
# Decision priority:
#   1. file_path not in watched set → ALLOW-OUTSIDE-SCOPE
#   2. recent (<=60min) artifact with all 4 sections filled → ALLOW-ARTIFACT
#   3. content contains `DCA-bypass: trivial — <reason>` AND diff <=20 lines
#      AND not touching process-critical sections → ALLOW-BYPASS (trivial)
#   4. content contains `DCA-bypass: substantive — <reason>` AND not touching
#      process-critical sections → ALLOW-BYPASS (substantive), logged
#   5. content touches process-critical sections → BLOCK/ADVISE (no bypass)
#   6. default → BLOCK/ADVISE, create stub artifact, point to the skill
#
# Configuration (environment variables):
#   DCA_ENFORCE=1        hard-block (exit 2) instead of advisory reminder
#   DCA_ARTIFACT_DIR     where artifacts live (default: ~/.claude/dca)

set -euo pipefail

DCA_DIR="${DCA_ARTIFACT_DIR:-$HOME/.claude/dca}"
AUDIT_LOG="$DCA_DIR/_audit.log"
BYPASS_LOG="$DCA_DIR/_bypass_log.md"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEMPLATE="$PLUGIN_ROOT/assets/TEMPLATE.md"
DCA_ENFORCE="${DCA_ENFORCE:-0}"       # 0 = advisory (default), 1 = hard block
DCA_QUIET="${DCA_QUIET:-0}"           # 1 = suppress the advisory reminder (still logs); ignored in enforce mode
FRESHNESS_MINUTES=60
TRIVIAL_MAX_LINES=20

# Process-critical section markers — these never accept a bypass marker.
# Universal Claude Code surface: settings.json hook-configuration keys. Editing
# these changes what runs on every tool call, so they warrant the full process.
PROCESS_CRITICAL_PATTERNS=(
  '"hooks"[[:space:]]*:'
  '"PreToolUse"[[:space:]]*:'
  '"PostToolUse"[[:space:]]*:'
  '"matcher"[[:space:]]*:'
)

ts_now() { date +%Y-%m-%dT%H:%M:%S%z; }

log_decision() {
  # $1 = decision, $2 = file, $3 = reason
  mkdir -p "$DCA_DIR"
  printf '%s %s %s %s\n' "$(ts_now)" "$1" "${2:-?}" "$3" >> "$AUDIT_LOG" 2>/dev/null || true
}

allow() {
  log_decision "$1" "${2:-}" "${3:-}"
  exit 0
}

allow_outside_scope() {
  # Log OUTSIDE-SCOPE only when the target is inside a .claude config tree
  # (a watched-set-gap signal worth keeping). Unrelated project edits are
  # allowed silently — they carry no forensic value and dominate log volume.
  case "${1:-}" in
    *"/.claude/"*) log_decision "ALLOW-OUTSIDE-SCOPE" "${1:-}" "${2:-}" ;;
  esac
  exit 0
}

block() {
  # $1 = reason, $2 = file, $3 = optional extra stderr block.
  # Advisory (default): emit a reminder and allow (exit 0).
  # Enforce (DCA_ENFORCE=1): block the write (exit 2).
  local mode_label exit_code
  if [ "$DCA_ENFORCE" = "1" ]; then
    mode_label="BLOCK"; exit_code=2
  else
    mode_label="ADVISORY"; exit_code=0
  fi
  log_decision "$mode_label" "${2:-?}" "$1"
  # Show the message when enforcing (a block needs an explanation) or when not
  # quieted. DCA_QUIET=1 silences only the advisory reminder.
  if [ "$exit_code" = "2" ] || [ "$DCA_QUIET" != "1" ]; then
    {
      echo "[dca-gate] $mode_label: editing watched path ${2:-?}"
      echo "Reason: $1"
      echo
      if [ -n "${3:-}" ]; then
        printf '%s\n' "$3"
        echo
      fi
      echo "Run the debate-critique-agreement skill for process-critical changes."
      [ "$exit_code" = "0" ] && echo "(advisory mode — set DCA_ENFORCE=1 to hard-block instead)"
    } >&2
  fi
  exit "$exit_code"
}

# ---- Parse stdin -----------------------------------------------------------

STDIN_JSON="$(cat)"

# Fast path (perf) — the ~99% of tool calls that touch no watched path exit HERE
# without spawning python3 (~3 cold-starts → ~2ms). De-escape JSON backslashes
# first so slash-escaped paths (\/.claude\/) still match, and match markers with
# NO leading slash so absolute AND relative forms both hit. The marker set is a
# superset of is_watched_path() below → no false-negative; a false positive just
# falls through to the precise check (safe). An obfuscated path could slip past —
# already out of scope (this is a forgetfulness guard, not an adversarial guard).
case "${STDIN_JSON//\\/}" in
  *CLAUDE.md*|*.claude/settings*|*.claude/hooks/*|*.claude/skills/*) : ;;  # maybe watched → full check
  *) exit 0 ;;                                                             # definitely not → fast exit
esac

parse_field() {
  # $1 = field path, e.g. "tool_input.file_path"
  printf '%s' "$STDIN_JSON" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  parts = '$1'.split('.')
  v = d
  for p in parts:
    v = v.get(p) if isinstance(v, dict) else None
    if v is None: break
  if v is None:
    print('')
  elif isinstance(v, (list, dict)):
    print(json.dumps(v))
  else:
    print(v)
except Exception:
  print('')
" 2>/dev/null
}

TOOL_NAME=$(parse_field "tool_name")
FILE_PATH=$(parse_field "tool_input.file_path")

# Resolve symlinks for matching (e.g. ~/.claude/CLAUDE.md → a dotfiles checkout).
RESOLVED_PATH=""
if [ -n "$FILE_PATH" ]; then
  RESOLVED_PATH=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
fi

# ---- Scope check -----------------------------------------------------------

is_watched_path() {
  local p="$1"
  case "$p" in
    */CLAUDE.md) return 0 ;;
    */.claude/settings.json) return 0 ;;
    */.claude/settings.local.json) return 0 ;;
    */.claude/hooks/*) return 0 ;;
    */.claude/skills/*) return 0 ;;
  esac
  return 1
}

# ---- Bash matcher: forgetfulness-guard for write-verb patterns -------------
# A conservative regex-only detector for common write verbs (sed -i, tee,
# heredoc redirect) targeting watched paths. Adversarial bypass (variable
# expansion, eval, subshells, command substitution, base64 payloads, nested
# shells) is intentionally out of scope — see the skill's "Known limitations".

if [ "$TOOL_NAME" = "Bash" ]; then
  BASH_CMD=$(parse_field "tool_input.command")
  BASH_TARGET=$(printf '%s' "$BASH_CMD" | python3 -c "
import sys, re, os
cmd = sys.stdin.read()
home = os.environ.get('HOME', '')

# Anchored to command-start (^ or after \\n;&|) so tokens inside quoted
# strings / heredoc bodies don't match. Each pattern captures the path in group 1.
ANCHOR = r'(?:^|[\\n;&|])\\s*'
patterns = [
    ANCHOR + r'sed\\b[^|;&\\n]*?\\s+-i\\b[^|;&\\n]*?\\s+([~/][\\w./_-]+)',
    ANCHOR + r'tee\\b\\s+(?:-a\\s+)?([~/][\\w./_-]+)',
    ANCHOR + r'cat\\b\\s*<<-?\\s*[\"\\']?\\w+[\"\\']?[^>\\n]*>>?\\s*([~/][\\w./_-]+)',
]

for pat in patterns:
    m = re.search(pat, cmd)
    if m:
        p = m.group(1).rstrip('\\'\"')
        if p.startswith('~/'):
            p = home + p[1:]
        elif p == '~':
            p = home
        print(p)
        break
" 2>/dev/null)

  if [ -z "$BASH_TARGET" ]; then
    exit 0
  fi

  BASH_REAL=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$BASH_TARGET" 2>/dev/null || echo "$BASH_TARGET")

  if ! { is_watched_path "$BASH_TARGET" || is_watched_path "$BASH_REAL"; }; then
    allow_outside_scope "$BASH_TARGET" "bash-target-not-watched"
  fi

  # Promote Bash target to FILE_PATH so downstream checks operate on it.
  FILE_PATH="$BASH_TARGET"
  RESOLVED_PATH="$BASH_REAL"
fi

if [ -z "$FILE_PATH" ] || ! { is_watched_path "$FILE_PATH" || is_watched_path "$RESOLVED_PATH"; }; then
  allow_outside_scope "$FILE_PATH" ""
fi

# ---- Content extraction ----------------------------------------------------

CONTENT=$(printf '%s' "$STDIN_JSON" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  ti = d.get('tool_input', {}) or {}
  tn = d.get('tool_name', '')
  out = []
  if tn == 'Write':
    out.append(ti.get('content','') or '')
  elif tn == 'Edit':
    out.append(ti.get('new_string','') or '')
    out.append(ti.get('old_string','') or '')
  elif tn == 'MultiEdit':
    for e in ti.get('edits', []) or []:
      out.append(e.get('new_string','') or '')
      out.append(e.get('old_string','') or '')
  elif tn == 'Bash':
    out.append(ti.get('command','') or '')
  print('\n---DCA-SEP---\n'.join(out))
except Exception:
  print('')
" 2>/dev/null)

# ---- 1. Recent artifact check ---------------------------------------------

mkdir -p "$DCA_DIR"
recent_artifact=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  basename_f=$(basename "$f")
  case "$basename_f" in
    TEMPLATE.md|README.md|_*) continue ;;
  esac
  # Completeness: 4 headers present, no unfilled DCA-FILL-ME markers, and a
  # Convergence section containing a concession / no-concession / per-leg block.
  if grep -q '^## Question' "$f" \
     && grep -q '^## Codex' "$f" \
     && grep -q '^## Opus' "$f" \
     && grep -q '^## Convergence' "$f" \
     && ! grep -q 'DCA-FILL-ME' "$f" \
     && grep -qE '\*\*(Codex-?conceded|Opus-?conceded|Concessions|No concessions|Unresolved disagreements|Unresolved|Cross-perspective overlap|Non-overlap)' "$f"; then
    recent_artifact="$f"
    break
  fi
done < <(find -L "$DCA_DIR" -maxdepth 1 -name '*.md' -type f -mmin -"$FRESHNESS_MINUTES" 2>/dev/null | sort -r)

if [ -n "$recent_artifact" ]; then
  allow "ALLOW-ARTIFACT" "$FILE_PATH" "via $(basename "$recent_artifact")"
fi

# ---- 2. Process-critical detection ----------------------------------------

is_process_critical=false
for pat in "${PROCESS_CRITICAL_PATTERNS[@]}"; do
  if printf '%s' "$CONTENT" | grep -qE "$pat"; then
    is_process_critical=true
    break
  fi
done

# ---- 3. Bypass detection ---------------------------------------------------

BYPASS_PARSED=$(printf '%s' "$CONTENT" | python3 -c "
import sys, re
text = sys.stdin.read()
# Match em-dash, en-dash, or hyphen as the separator.
m = re.search(r'DCA-bypass:\s*(trivial|substantive)\s*[—–\-]\s*([^\r\n]+)', text)
if m:
    print(m.group(1))
    print(m.group(2).strip())
" 2>/dev/null)
tier=$(printf '%s' "$BYPASS_PARSED" | sed -n '1p')
reason=$(printf '%s' "$BYPASS_PARSED" | sed -n '2p')

if [ -n "$tier" ]; then

  if $is_process_critical; then
    block "process-critical section touched — bypass NOT allowed" "$FILE_PATH" \
      "Process-critical markers (hooks / PreToolUse / PostToolUse / matcher config) require a full DCA artifact.

Create one:
  ts=\$(date +%Y%m%dT%H%M%S)
  cp \"$TEMPLATE\" \"$DCA_DIR/\${ts}_<topic>.md\"
Fill all 4 sections (Question/Codex/Opus/Convergence) then retry."
  fi

  if [ "$tier" = "trivial" ]; then
    line_count=$(printf '%s' "$CONTENT" | wc -l | tr -d ' ')
    if [ "${line_count:-0}" -gt "$TRIVIAL_MAX_LINES" ]; then
      block "marked trivial but diff is ${line_count} lines (>${TRIVIAL_MAX_LINES})" "$FILE_PATH" \
        "Use 'DCA-bypass: substantive — <reason>' instead, or split into smaller commits."
    fi
    allow "ALLOW-BYPASS-TRIVIAL" "$FILE_PATH" "$reason"
  else
    printf '%s\t%s\t%s\t%s\n' "$(ts_now)" "$FILE_PATH" "substantive" "$reason" >> "$BYPASS_LOG"
    allow "ALLOW-BYPASS-SUBSTANTIVE" "$FILE_PATH" "$reason"
  fi
fi

# ---- 4. Default: reminder (advisory) or block (enforce) --------------------

if $is_process_critical; then
  extra="This edit touches a process-critical section (hooks / matcher config). Running debate-critique-agreement first is strongly recommended."
else
  extra="No DCA artifact or bypass marker present. For process-critical changes, running debate-critique-agreement is recommended; otherwise proceed."
fi

block "watched path edited without a DCA artifact or bypass marker" "$FILE_PATH" "$extra"
