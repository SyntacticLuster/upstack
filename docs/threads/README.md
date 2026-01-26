# UPSTACK — Threads Archive

This directory preserves **WORK, TRIAGE, and CONTRACT thread outputs** generated during development.
These documents are **authoritative design and process artifacts**, but they are **not CANON**.

If CANON is the ledger of verified truth, this folder is the memory of *how and why we decided things*.

Nothing here is speculative, but nothing here is automatically true either.

---

## What belongs here

This folder contains:

- **WORK thread outputs**  
  Concrete implementation guidance, scope definitions, and constraints reviewed and agreed upon.

- **TRIAGE protocols and postmortems**  
  Rules for bug fixing, regressions, and incident handling.

- **Thread contracts**  
  Formal definitions of what each thread type is allowed to do and forbidden from doing.

These files exist to prevent:

- re-deriving decisions from memory
- re-litigating settled scope boundaries
- repeating work because “we forgot we already solved this”

---

## What does NOT belong here

- Verified runtime truth  
  → That goes in `/docs/CANON.md`.

- Implementation activity logs  
  → That belongs in `/docs/WORK.md` or commit history.

- Future plans, ideation, or “what if” discussions  
  → Those belong in chat or draft notes, not here.

- Silent rewrites  
  → History is preserved. Revisions must be explicit.

---

## Directory structure

/docs/threads
README.md ← this file
/contracts
THREAD_CONTRACTS.md ← master definitions of thread types
WORK_SIM.md ← reviewed WORK thread outputs
WORK_TOWER.md
WORK_RENDER.md
WORK_MODULES.md
WORK_UI.md
TRIAGE_PROTOCOL.md

Each file represents the **output** of a reviewed thread, not the initial prompt.

---

## File format rules

Every thread file should begin with a small header:

THREAD: UPSTACK — `NAME`
THREAD_TYPE: WORK | TRIAGE | CONTRACT
SCOPE: `paths or domains`
VERSION: v0.X
LAST_REVIEWED: YYYY-MM-DD

Followed by the **verbatim reviewed output**.

No embellishment. No rephrasing.

---

## Revisions (important)

These files are not append-only, but they are **revisioned**.

If you need to change something, add a revision block at the top:

REV v0.2 (2026-01-26)

Clarified deterministic ordering for ModuleDB indexes.

Reason: prevent cross-platform ordering differences.

Never silently edit content.  
If it matters, it gets a REV entry.

---

## Relationship to CANON

- **Threads inform CANON**
- **Threads do not become CANON automatically**
- CANON entries must be:
  - implemented
  - observed
  - evidenced

If a fact graduates from intent to reality, it is copied into CANON as an `ADD` or `PATCH` with evidence.

---

## Why this exists

This folder exists because:

- memory is unreliable
- chat history is not a system
- redoing work is unacceptable

If you are about to make a decision and think:
> “Didn’t we already cover this?”

You should be looking here.

If you are about to change behavior and think:
> “Why are we doing it this way?”

You should be looking here.

If it’s not here, it’s probably not settled.

---

**Discipline here buys speed later.**
