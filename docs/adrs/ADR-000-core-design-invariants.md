# ADR-000: Core Design Invariants

## Status

Accepted (Seed)

## Context

UPSTACK is a systems-driven survival strategy game focused on resource management, constrained growth, and long-term consequences. The primary design goal is not power fantasy or infinite optimization, but the gradual discovery that survival decisions accrue structural and moral debt over time.

This ADR establishes the non-negotiable invariants that define the game’s identity. All future mechanics, systems, and content must comply with these constraints. If a feature conflicts with an invariant, the feature is wrong by definition.

---

## Design Invariants

1. **The world is finite**
   - The playable environment has hard limits.
   - Apparent abundance may exist early, but infinite expansion is impossible.
   - The player may not learn these limits immediately.

2. **Growth increases fragility**
   - Expanding population, capacity, automation, or territory always increases system complexity and failure surface area.
   - There is no growth path that only adds upside.

3. **There is no permanent equilibrium**
   - The game does not permit a stable, solved end-state.
   - Pressure may be delayed or redistributed, but never eliminated.

4. **Optimization creates future debt**
   - Efficient decisions solve immediate problems while increasing long-term risk.
   - Debt may manifest as scarcity, threat, sabotage, social instability, or loss of flexibility.

5. **Automation shifts failure modes**
   - Automated systems reduce player burden but introduce new, often less visible risks.
   - Automation never removes consequences, it only hides or delays them.

6. **Failure must be legible**
   - When the player fails, the cause should be traceable to prior decisions.
   - Failure should feel earned, not random or punitive.

7. **The game does not moralize explicitly**
   - There are no binary good/evil choices.
   - The system does not judge intent, only outcomes.
   - Moral weight emerges from consequences, not narration.

8. **Responsibility precedes readiness**
   - The player may acquire dependents, obligations, or liabilities before they are fully equipped to support them.
   - These responsibilities are systemic, not cosmetic.

9. **Information is imperfect but not deceptive**
   - The game may withhold information.
   - It may not lie about how systems function.
   - Revelation timing is a design tool.

---

## Explicit Rejections

The following are intentionally excluded from UPSTACK’s design space:

- Infinite or procedurally endless worlds
- “Win forever” or stable optimization endgames
- Purely cosmetic morality systems
- Upgrades that permanently solve a core pressure
- Failure driven primarily by random chance
- Systems that fully automate survival without tradeoffs

---

## Deferred Questions

The following topics are acknowledged but intentionally unresolved:

- The mechanical representation of population growth and dependents
- How sabotage is detected, mitigated, and escalated
- What constitutes a “win” versus a “successful extraction”
- How much information about world limits is eventually revealed
- The balance between abstraction and embodiment of civilians

These questions will be addressed in future ADRs as design decisions solidify.

---

## Consequences

By accepting this ADR:

- Design scope is intentionally constrained.
- Player discomfort is a feature, not a failure.
- Late-game tension is mandatory, not optional.
- “Fun” is subordinate to coherence.

Any future decision that violates these invariants must be rejected or justified via a superseding ADR.
