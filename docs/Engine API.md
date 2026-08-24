## Purpose

The types and procedures the engine provides to every script, independent of deployment. This is the surface an author may use without importing anything and without the host granting permission.

Distinct from the host embedding API, which covers capabilities a host chooses to expose to a guest module — input, audio, assets, storage, transport. Those are tracked in [Runtime & Deployment](Runtime%20&%20Deployment.md#not-yet-written). Anything in this document is present everywhere a script runs, so adding to it is a portability commitment.

Contents are largely unsettled; see [Pending](Pending.md#core-api).

---

## Boundary

Three rules decide whether something belongs here rather than in the language or in the host API.

- **Pure computation over values the caller already holds.** Vector math, interpolation, clamping, trigonometry, distance between two supplied points. These have no ECS visibility and no side effects.
- **Nothing that finds, selects, or relates entities.** Locating entities is the query language's job. A core-API entry that returns entities by proximity or by predicate would move query surface out of the language and past the reordering and costing rules that apply there — see [No general indexing or materialization](Design%20Principles.md#no-general-indexing-or-materialization).
- **Portable by construction.** No entry may expose word size, endianness, or platform identity, per [Scripts are portable](Design%20Principles.md#scripts-are-portable).

---

## Areas

Mock scripts have already relied on the following, none of it yet specified:

- **Math.** Scalar arithmetic beyond the operators, trigonometry, interpolation, clamping.
- **Vectors.** Vector types, their operators, and value constants such as a unit direction. Value constants are unresolved in the language itself — see [Pending](Pending.md#data-modeling-and-declaration-syntax).
- **Geometry.** Predicates over supplied points and shapes, such as whether two positions are within a distance. Note the boundary rule: a predicate over two given points belongs here; finding the points does not.
- **Randomness.** Generation over a range. Unresolved: whether the generator is deterministic and seeded per peer, which matters because state is bulk-synchronized and two peers disagreeing on a draw is a desync rather than a cosmetic difference.
- **Timing.** Elapsed time for the current tick, the tick counter, and a timer type. See [Pending](Pending.md#core-api) for the timer proposal and the tick-origin hazard it carries.

---

## Not Yet Written

- Every entry above. The areas are a record of what scripts assume, not a specification of what exists.
- Naming and namespacing: whether core entries are bare names, or grouped under a prefix, and whether that grouping is a language construct or a convention.
- Whether any of this is versioned independently of the language, and what a script may assume when running against a newer engine.
