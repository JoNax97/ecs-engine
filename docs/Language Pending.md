## Not Yet Specified
 
The following areas are known to be part of the language but have not been
resolved in this specification:
 
- Memory tiers, handle-validity states, and null/absence semantics
  (carried over from an earlier design layer, not yet reconciled with the
  constructs above).

- Generics and trait/conformance syntax.

- Storage location for payload data on symmetric or many-to-many
  relationships, which have no single owning side.

- Declaration syntax for custom, game-level events (e.g. `player_joined`)
  beyond the built-in `tick` / `changed` / `load` triggers. Binding a
  parameterized event to a query/proc without the trigger's parameter
  colliding with a `with`-bound name (e.g. `on dead(unit)` alongside a
  `with`-bound `unit`) is parked pending this.

- Quantified negation over a relationship or sub-match ("no entity related
  to this one satisfies X") — identified as a real gap, no syntax chosen.

- Syntax for direct iteration over a bound relationship's targets outside
  a query (e.g. given a held `Entity`, iterating its `Children`) — sketched
  as reusing the existing `for ... in` loop form, not finalized.

- Whether `sum`/`count` reductions over a live query can be maintained
  incrementally (updated on write rather than rescanned on read) — would
  require exposing the prior value on a `changed` event, which is not yet
  designed. Mechanism sketched: hook the
  existing dirty-bitmap/version-per-block change detection and update a
  running accumulator on write, rather than building new infrastructure.
  Deferred rather than solved: access to previous values is a requirement
  on the ECS design itself, and belongs in the requirement list gathered
  when that design happens, not here.

- Error handling

- System scheduling and dependency declaration. Related and unresolved:
  whether **systems become a first-class construct**. They were previously
  judged unnecessary — a query bound to a trigger already covers what a
  system does — but expressing dependencies may require a named, addressable
  thing to hang them on, and anonymous self-driving queries give nothing to
  reference. Raised in conversation with a colleague; not previously written
  down anywhere.

  Note the doc is currently inconsistent on this: [ECS focused](Design%20Principles.md#ecs-focused)
  lists systems among the primitives the design is organized around, while
  the language has no system construct at all.
  
- Field syntax
  
- Value constants (like Vector3.left)

### Jose's suggestions

- Alternative ternary syntax (with condition first)
- Null coalescing operator
- Optional fields (plus bit-packing idea) 
- Reorder declarations ("name sandwiched between type and annotations")
- Re-evaluate array/cardinality syntax
- Pseudo-catching errors:
	- proc calls automatically propagate failures upwards
	- some keyword can be used to catch them

---

## Open Discrepancies

Points where the spec does not yet follow through on a stated design principle. Recorded for review, not resolved.

**Load-time branch elimination is an optimization, not a guarantee.** Deliberate — evaluating the condition at run time is equally correct, so promising elimination would over-constrain the backend. But it leaves an author with no language-level assurance that a branch behind an absent module costs nothing, which is the shape of implicit cost [No hidden control flow, no implicit costs](Design%20Principles.md#no-hidden-control-flow-no-implicit-costs) rules out.

Resolution direction: tooling rather than spec — surface what was stripped and what survived, per [Show the machinery in motion](Design%20Principles.md#show-the-machinery-in-motion). A guarantee stated in the language would buy the same confidence at the cost of pinning the backend.

**Component field legality is unstated.** The engine synchronizes state as per-frame chunk copies, so a component's fields must be flat-copyable. `integer Slots[]` (unbounded, dynamically backed) and variable-length `string` are not, yet nothing in [Primitive Types](Language%20Spec.md#primitive-types) forbids them inside a component — and the unsafe form is one character shorter than the safe one (`Slots[]` vs `Slots[30]`), making it the easier thing to write. [Strings](Language%20Spec.md#strings) notes fixed-length strings are component-usable, implying the variable form is not, but never states the rule directly.

Resolution direction: first-class constructs for the cases that genuinely need pointer-like data (e.g. chunk-managed buffers). Not yet designed. The legality rule should be stated explicitly regardless.

Mechanism sketched: eligibility is decided by taint propagation — an unbounded array taints the `value` containing it, and the taint propagates outward to disqualify any component holding it. This reuses the previous iteration's struct-tier inference wholesale, including the trick of storing the offending field path alongside the taint at declaration time, so reporting a failure does not require re-walking the type.

**`changed(Component)` has no defined meaning on a non-owning peer.** Remote state arrives as a raw chunk write rather than a script-initiated mutation. If the engine diffs received chunks and fires `changed`, that is a recurring per-frame cost, against the no-implicit-costs principle. If it does not fire, reactive gameplay code behaves differently on owning and remote peers, which is precisely the networking awareness the design aims to remove. Unresolved; the language cannot stay silent, as `changed` is author-visible.

**The documented `with`/`where` boundary is not the one that costs.** [Clauses](Language%20Spec.md#clauses) presents the split in cost terms (fixed presence/bitmap check vs. per-entity runtime evaluation) and then disclaims that it constrains the compiler at all. Both are correct under the intended model: `with` and `where` together form one declarative matching region the compiler may reorder and optimize freely — for instance, servicing a `distance(...)` predicate from a spatial partition rather than per entity. `do` is a freeform imperative block and is largely opaque to that optimization.

The load-bearing boundary is therefore `where` vs. `do`, and the spec does not mention it. An author who hoists a predicate out of `where` into an early exit at the top of `do` — a refactor that looks purely cosmetic — silently forfeits acceleration and converts a partition lookup into a full scan. That is an implicit cost of exactly the kind the design forbids. (Related: no early-exit form inside `do` is currently specified.)

A second cost cliff sits inside `where`. If acceleration depends on the compiler recognizing specific predicate shapes, then predicates that match a known form are cheap and equivalent-but-unrecognized ones degrade to per-entity scans, with nothing in the syntax distinguishing them. Either the recognized set is specified, or `where` needs a restricted grammar.

**`=` for both declaration and reassignment is a pit-of-failure case.** [Declaration and assignment](Language%20Spec.md#declaration-and-assignment) fixes a name's type at first use in a scope; every later use reassigns. A misspelled name therefore declares a new variable with an inferred type instead of raising an error. To revisit alongside field declaration syntax, which is also pending.

**TODO: `LoomScript Examples.md` and the spec disagree.** Partly aspirational syntax, partly spec lag; each divergence needs resolving in one direction. Current list:

- `Vector3.left` — value constants are unresolved (see Not Yet Specified above).
- `create entity with (...)` uses parentheses; [Creation](Language%20Spec.md#creation) omits them.
- `for entity with Position, Velocity do` — no parentheses around the binding, unlike every example in [Queries](Language%20Spec.md#queries).
- `entity.position.value` — lowercase field access against a `Position` component; casing convention for component access is unstated.

**Ownership and `non_serialized` have layout consequences.** Both partition storage: a chunk cannot be blind-copied in a single direction if ownership varies within it, and a non-serialized component cannot share a chunk with synced data. The engine is expected to organize memory so layout matches these constraints — the same mechanism that will cover streaming/partial loads and interest management. Open at the language level: how ownership is expressed. Expressing it structurally (a tag or relationship rather than a field) would let archetype partitioning segregate owned from remote entities automatically, and keep it a free presence check in `with`.

---

## Mechanism Without a Contract

Features with implementation reasoning already worked out but no syntax or semantics in the language spec. Recorded so the reasoning is not lost a third time; recording it is not a commitment to the feature.

**`requires` on components.** An alternative to inheritance: a component declares a dependency on another. Cascade-removal reuses the existing end-of-frame flush pass, the same mechanism as relationship deletion — reuse, not new machinery. No syntax, no semantics for conflicts or diamond cases.

**Transitive relationship traversal.** Needs a real graph walk, and is the one query construct whose cost is genuinely runtime-dependent rather than bounded by the match set. No depth bound decided; see the bounded-execution contradiction below. Listed as a TODO in the spec's Relationships section, alongside ephemeral and exclusive relationships.

**Wildcard / `any` relationship terms.** Compile to presence-only bitmap checks with no target materialization — the cheapest possible form, and a distinct codegen path from the named-target case. Named-target terms compile to forward relationship lookups, O(1) per match: a direct index or pointer chase on the source entity's relationship data, not a general join algorithm. Named targets that are never used can be optimized away by static analysis.

**`parallel`.** Highly speculative, and it is not the real design — it sits on top of one that does not exist yet.

The intended model is that the engine builds a DAG from declared dependencies (syntax also pending, listed above as system scheduling) plus whatever parallelization opportunities it can infer, and executes scripts in that order. A `parallel` annotation might end up as one knob the author has over that behaviour, or might not exist at all. Too early to tell.

What is worth keeping either way: with no author-declared read/write sets, conflict detection requires the compiler to extract per-field access statically. That analysis is what would make any such knob a checked hint rather than an unverified claim. See the access-sets contradiction below.

**Frame-tier memory.** Bump-allocated, discarded at frame end. Referenced by the GroupBy entry below. Memory tiers as a whole are already listed above as carried over from the previous iteration and unreconciled.

### Deferred backend ideas

Worked through in design conversation and deliberately not adopted. Recorded because each is a real option the design may need later, and because each has a specific reason it is not needed now.

**Load-time codegen.** Folding load-time-known values into native code during the Wasm-to-native step at load, rather than emitting indirection for them. Would make any load-time-resolved constant free at run time instead of costing a lookup. Not needed while the only load-time fact is module presence, since a presence check is a branch rather than a value feeding computation. Becomes relevant the moment a load-time value participates in layout.

**Load-time checking of dependency versions.** Allowing a manifest to admit a *range* of versions per dependency, with guards (`module.version >= 2`) selecting between implementations. The rule that makes it sound: unguarded code type-checks against the range's **floor**, and guards narrow only *upward*. Writes check against the floor, reads against the ceiling, so both stay statically decidable without enumerating configurations. Deferred because a single declared version per dependency removes the problem entirely, and version skew is a mod-ecosystem concern that will be designed better against real modules than in the abstract.

**Virtualized data layouts.** Scripts addressing fields through a layout table populated at load, rather than baking static offsets. Would let a type's size or field widths vary per deployment while keeping one portable artifact. Rejected for now on the honest-costing bar: it puts an indirection on every field access to buy configuration flexibility that [Scripts are portable](Design%20Principles.md#scripts-are-portable) says the engine should be absorbing instead.

Related and dropped outright rather than deferred: **two-tier compilation** (mods compiled once and portably, internal modules compiled per target). It resolves the same tension, but by giving up the single-artifact guarantee, and it splits the backend into two paths where the less-tested one is the one shipped to third parties.

### Shelved with rationale

**GroupBy.** Ruled out of the query language, but worth recording why the ruling might not hold. The objection that killed it was that materialized results reopen the heap-in-component hazard — and that objection does not apply if the result is scoped to frame-tier memory: bump-allocated, discarded at frame end, never touching a component. A transient, non-addressable GroupBy is therefore technically safe. It was rejected on the honest-costing bar instead — it did not clearly earn its cost — which is a design-taste call, not an architectural blocker. Revisit if a real use case appears.

---

## Contradictions with the Previous Iteration

[Previous Iteration](Previous%20Iteration.md) is outdated by design. These are points where it takes a position the current design has moved away from. Recorded so the divergence is deliberate rather than accidental.

**Access sets — resolved, goes fully implicit.** The previous design required explicit per-query read/write declarations, on the grounds that "conflict detection requires declared, not inferred, access sets". The current position is the opposite: no author-declared access, with the compiler statically extracting per-field read/write sets from imperative bodies. Open consequence: that analysis pass is what makes parallelism a safe hint rather than an unchecked claim, and it is assumed everywhere but specified nowhere.

**Storage model — undecided, needs its own design pass.** Two candidates, both still live:

- *Archetype/table storage.* Entities are grouped by component set and stored contiguously. Hazard identified previously: adding a component to one entity can swap-remove and relocate an unrelated entity in the same table, invalidating handles held to it mid-frame. Deferring removal does not fix this, because adds relocate too.
- *Inverted hierarchical bitmap storage.* Each component owns a presence bitmap over fixed entity slots; entities never move. Eliminates the relocation hazard structurally rather than mitigating it. Empty bitmap blocks do not materialize storage, so the memory cost depends on entity-ID clustering rather than on the architecture.

Until this is settled, "chunk" (interchangeably "table") is used throughout to mean the most granular partition that holds components, without committing to what that partition actually is. The ownership entry above goes further and presumes archetype partitioning, which it has not earned.

**Indexing — position refined, not reversed.** The previous phrasing ("don't build indexing infra unless profiling justifies it") reads as a blanket prohibition. The actual stance is narrower: generalized, SQL-style materialized result sets are rejected outright, but individual features are evaluated case by case for whether they can ride existing infrastructure and deliver enough value. Spatial partitioning for `distance(...)` predicates is therefore a candidate to evaluate, not a violation. See [No general indexing or materialization](Design%20Principles.md#no-general-indexing-or-materialization).

**Hot reload — unreconciled.** Previously treated as an engine-side concern, explicitly outside language design. The current notes place it squarely in the compiler: per-module incremental compilation, with cross-module symbol linkage that stays stable while one module is recompiled and others are not.

**Bounded execution — unreconciled, and newly reopened.** The previous design flagged loop and recursion limits for determinism as needed but undesigned, noting there is no GC pause to blame instead. Transitive relationship traversal is the first construct with genuinely runtime-dependent cost and has no max-depth safeguard, which makes the gap concrete rather than theoretical.
