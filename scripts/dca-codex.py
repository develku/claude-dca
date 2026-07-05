#!/usr/bin/env python3
"""
Run the DCA cross-model critique via `codex exec`, actively monitoring the event
stream for liveness instead of blocking on one long timeout.

The problem this solves: a plain `codex exec` (or a single subprocess timeout)
makes the caller wait out the entire hard cap even when codex has silently hung.
This helper polls the `--json` event stream and bails FAST when the stream stops
growing (stall), so the caller "checks first" instead of waiting blindly. It
also kills the whole codex process group, so nothing lingers after a bail.

Usage:
  dca-codex.py <prompt_file> [--stall 150] [--hard 300] [--outdir DIR] [--model M]

Exit codes:
  0    completed — final message on stdout
  124  stalled / timed out / exited with no output
  127  codex CLI not found

A one-line JSON status is always printed to stderr:
  {"status": ok|stalled|timeout|error|missing, "reason": ..., "thread_id": ..., "seconds": N}
"""
import argparse, json, os, signal, subprocess, sys, time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt_file")
    ap.add_argument("--stall", type=int, default=150,
                    help="abort if the event stream gains no new bytes for N seconds "
                         "(conservative: --json events are milestones, not heartbeats)")
    ap.add_argument("--hard", type=int, default=300, help="absolute maximum seconds")
    ap.add_argument("--outdir", default="/tmp")
    ap.add_argument("--model", default=None, help="override the codex model")
    ap.add_argument("--poll", type=float, default=3.0)
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    events = os.path.join(args.outdir, "dca_codex_events.jsonl")
    last = os.path.join(args.outdir, "dca_codex_last.txt")
    open(events, "w").close()
    open(last, "w").close()

    cmd = ["codex", "exec", "-s", "read-only", "--json", "-o", last]
    if args.model:
        cmd += ["-m", args.model]

    def status(**kw):
        print(json.dumps(kw), file=sys.stderr)

    try:
        pf = open(args.prompt_file)
        ev = open(events, "w")
        proc = subprocess.Popen(cmd, stdin=pf, stdout=ev,
                                stderr=subprocess.DEVNULL, text=True,
                                start_new_session=True)
    except FileNotFoundError:
        status(status="missing", reason="codex CLI not found", thread_id=None, seconds=0)
        return 127

    def kill():
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except Exception:
            pass

    start = time.monotonic()
    last_size = -1
    last_growth = start
    thread_id = None
    completed = False

    while True:
        rc = proc.poll()
        try:
            size = os.path.getsize(events)
        except OSError:
            size = 0
        now = time.monotonic()

        if size != last_size:
            last_size, last_growth = size, now
            try:
                with open(events) as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except ValueError:
                            continue
                        if obj.get("type") == "thread.started":
                            thread_id = obj.get("thread_id", thread_id)
                        elif obj.get("type") == "turn.completed":
                            completed = True
            except OSError:
                pass

        if rc is not None:
            elapsed = round(now - start)
            has_output = os.path.getsize(last) > 0
            if completed or has_output:
                status(status="ok", reason="", thread_id=thread_id, seconds=elapsed)
                sys.stdout.write(open(last).read())
                return 0
            status(status="error", reason=f"codex exited rc={rc} with no output",
                   thread_id=thread_id, seconds=elapsed)
            return 124

        if now - last_growth > args.stall:
            kill()
            status(status="stalled", reason=f"no new events for {args.stall}s",
                   thread_id=thread_id, seconds=round(now - start))
            return 124

        if now - start > args.hard:
            kill()
            status(status="timeout", reason=f"hard cap {args.hard}s reached",
                   thread_id=thread_id, seconds=round(now - start))
            return 124

        time.sleep(args.poll)


if __name__ == "__main__":
    sys.exit(main())
