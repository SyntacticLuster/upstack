# UPSTACK — Thread Contracts

THREAD: UPSTACK — `THREAD_CONTRACTS`
THREAD_TYPE: `CONTRACT`
SCOPE: `documentation and process`
VERSION: `v0.1`
LAST_REVIEWED: `2026-01-26`

This document defines the standard thread formats and hard boundaries for UPSTACK development threads.

This file is not CANON. It describes process and constraints, not verified runtime truth.

---

## Canonical thread types

### CANON

Purpose: record verified truth only.

Source of truth: `/docs/CANON.md`.

This document does not restate CANON rules to avoid duplication drift. If there is disagreement, CANON.md wins.

---

### WORK

Purpose: scoped implementation guidance and constraints.

Allowed:

- design constraints
- schemas and interfaces
- acceptance criteria
- determinism rules
- explicit scope boundaries

Forbidden:

- recording unverified truth as fact
- runtime claims without evidence
- silent mutation of agreed constraints

Anything that becomes verified and observed must graduate to CANON with evidence.

---

### TRIAGE

Purpose: bug fixes and regressions only.

Allowed:

- minimal fixes restoring CANON behavior
- evidence-backed corrections
- reversible, localized changes

Forbidden:

- new features
- refactors without necessity
- balance or tuning changes
- speculative fixes

---

## Standard thread header

Every thread file must begin with the following header:

THREAD: UPSTACK — `NAME`
THREAD_TYPE: `WORK | TRIAGE | CONTRACT`
SCOPE: `paths or domains`
VERSION: `v0.X`
LAST_REVIEWED: `YYYY-MM-DD`

This header is mandatory. Missing fields are a contract violation.

---

## Global boundaries (apply everywhere)

- Rendering consumes simulation state and does not decide gameplay.
- UI reflects simulation state and does not mutate state except via explicit hooks.
- Modules are declarative data only; no simulation logic inside definitions.
- Simulation and events must be deterministic (stable ordering, seeded RNG).
- Anything verified and observed graduates to CANON with evidence.

These boundaries apply across all thread types unless explicitly overridden by CANON.

---

## Pointer map

- Verified truth: `/docs/CANON.md`
- Work activity log: `/docs/WORK.md`
- Bugfix discipline: `/docs/TRIAGE.md`
- Rationale and ADRs: `/docs/DECISIONS.md`
- Thread outputs archive: `/docs/threads/contracts/`

---

## Revision policy

Thread files are revisioned, not append-only.

Changes must be documented with a revision block at the top of the file:

REV vX.Y (YYYY-MM-DD)

- description of change
- reason for change

Silent edits are forbidden.

If it matters, it gets a revision entry.
