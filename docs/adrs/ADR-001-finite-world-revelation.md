# ADR-001: Finite World Revelation & Inevitable Exhaustion

## Status

Proposed

## Context

Following **ADR-000: Core Design Invariants**, early prototyping, playtesting, and comparative analysis have reinforced a central experiential truth:

> The most impactful failure in survival systems is not caused by scarcity itself, but by the delayed realization that scarcity was always inevitable.

Games that meaningfully explore survival tension do so by allowing players to *believe* in abundance long enough to invest emotionally, before confronting them with the system’s true limits.

This ADR formalizes how UPSTACK treats world finiteness, exploration, and the psychological timing of discovery.

---

## Decision

UPSTACK will implement a **Finite World with Delayed Legibility**, governed by the following principles.

### 1. The World Has Hard, Non-Negotiable Limits

- The playable world is finite in:
  - spatial extent
  - resources
  - long-term carrying capacity
- These limits are fixed at world generation.
- No upgrade, technology, or meta-system may remove or expand these limits.

### 2. Limits Are Discoverable, Not Declared

- The game does not explicitly announce world finiteness at the outset.
- Early play may reasonably suggest abundance or sustainability.
- Finiteness becomes undeniable only through:
  - perimeter discovery
  - resource exhaustion
  - systemic degradation

### 3. Exhaustion Is Gradual and Structural

- Resources do not disappear suddenly.
- Remaining options become:
  - increasingly distant
  - more dangerous
  - socially or morally costly
- Late-game survival reflects accumulated decisions, not sudden bad luck.

### 4. Discovery Timing Is a Core Design Lever

- The moment the player realizes “this is all there is” is intentional.
- Systems may:
  - delay recognition
  - soften its impact
  - allow temporary denial
- Systems may not prevent eventual realization.

### 5. Failure Is an Expected Outcome

- Eventual collapse is normal and anticipated.
- Success is measured by:
  - duration survived
  - condition preserved
  - damage deferred or redirected
- “Winning” is defined as extraction, not permanence.

---

## Implications

Acceptance of this ADR implies:

- Exploration inventories future regret.
- Optimization decisions accrue moral and systemic debt.
- Long-term equilibrium is impossible by design.
- Player discomfort is a signal of correct tuning, not a flaw.

The player should not ask:
> “How do I win?”

They should ask:
> “What did this make inevitable?”

---

## Non-Goals

This ADR does not define:

- World topology (island, continent, region, etc.)
- Procedural generation strategy
- Enemy or faction taxonomy
- Population, reproduction, or dependency mechanics

These will be addressed in subsequent ADRs and must comply with this framework.

---

## Consequences

If this ADR is adopted:

- Any mechanic that enables infinite growth or safety violates canon.
- Any system that appears benevolent must later reveal its cost.
- Playtests that feel comfortably sustainable indicate design failure.

UPSTACK is not a game about survival.
It is a game about realizing what survival already cost.
