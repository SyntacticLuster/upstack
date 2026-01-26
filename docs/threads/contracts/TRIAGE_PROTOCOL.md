# TRIAGE — PROTOCOL

THREAD: UPSTACK — TRIAGE
THREAD_TYPE: TRIAGE
SCOPE: `bug fixes and regressions only`
VERSION: v0.1
LAST_REVIEWED: 2026-01-26

Triage mode is surgery mode.

## Scope rules

- Fix bugs, crashes, regressions
- Restore CANON behavior
- No new features
- No refactors unless required

## Workflow

1. Identify regression
2. Isolate smallest fix
3. Verify against CANON
4. Produce evidence

## Output requirements

- What broke and why
- Files touched
- Verification run
- Rollback instructions

## Entry conditions

Triage begins only with:

- error output
- failing command
- commit regression range
- CANON violation reference

No speculation. No vibes.
