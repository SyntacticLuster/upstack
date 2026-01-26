# WORK — MODULES

THREAD: UPSTACK — MODULES
THREAD_TYPE: WORK
SCOPE: `res://scripts/sim/ModuleDef.gd, ModuleDB.gd`
VERSION: v0.1
LAST_REVIEWED: 2026-01-26

Modules are declarative data. They describe what exists, not what happens.

## Design posture

- No behavior
- No formulas
- No conditionals
- No lifecycle hooks

Simulation interprets modules. Modules do not act.

## ModuleDef schema

- id (immutable)
- display_name
- description
- category
- tags
- cost, mass, volume

### Capability descriptors

- provides
- consumes

Pure data only.

### Constraints

- requires_tags
- incompatible_tags
- tech_level
- faction

### Versioning

- schema_version
- deprecated
- replaced_by

Backward compatibility required.

## ModuleDB responsibilities

- Load all module defs
- Index by id, category, tag
- Structural validation only
- Read-only lookup

No sim logic. No mutation after load.

## Adding/removing modules

- Add: create new ModuleDef
- Remove: deprecate, never delete

## Acceptance criteria

- Declarative only
- No sim logic
- Backward compatible schema
