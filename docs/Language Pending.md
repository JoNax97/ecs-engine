## Purpose

Everything known to be unresolved, organized by area. Recording an item here is not a commitment to the feature — several entries exist to preserve reasoning that has already been re-derived more than once.

**Type** 
- `pending` (known gap, no design yet) 
- `discrepancy` (the spec does not follow through on a stated design principle) 
- `contradiction` (positions that conflict, with the previous iteration or internally)
- `mechanism` (implementation reasoning worked out, but no syntax or semantics) 
- `idea` (raised, not committed) 
- `shelved` (considered and deliberately not adopted)

**Importance** rated 1–5 by how much other work the item blocks, not by how large it is.

---

## Storage and Memory Layout

**Storage model** · `contradiction` · `5`

Undecided, needs its own design pass. Two candidates, both still live:

- *Archetype/table storage.* Entities are grouped by component set and stored contiguously. Hazard identified previously: adding a component to one entity can swap-remove and relocate an unrelated entity in the same table, invalidating handles held to it mid-frame. Deferring removal does not fix this, because adds relocate too.
- *Inverted hierarchical bitmap storage.* Each component owns a presence bitmap over fixed entity slots; entities never move. Eliminates the relocation hazard structurally rather than mitigating it. Empty bitmap blocks do not materialize storage, so the memory cost depends on entity-ID clustering rather than on the architecture.

Until this is settled, "chunk" (interchangeably "table") is used throughout to mean the most granular partition that holds components, without committing to what that partition actually is. The ownership entry below goes further and presumes archetype partitioning, which it has not earned.

This is the root blocker for the rest of this section, for `changed` on a non-owning peer, and for handle-validity semantics. It is an engine decision, and there is currently no engine design document — only [Design Principles](Design%20Principles.md).

**Component field legality is unstated** · `discrepancy` · `5`

The engine synchronizes state as per-frame chunk copies, so a component's fields must be flat-copyable. `integer Slots[]` (unbounded, dynamically backed) and variable-length `string` are not, yet nothing in [Primitive Types](Language%20Spec.md#primitive-types) forbids them inside a component — and the unsafe form is one character shorter than the safe one (`Slots[]` vs `Slots[30]`), making it the easier thing to write. [Strings](Language%20Spec.md#strings) notes fixed-length strings are component-usable, implying the variable form is not, but never states the rule directly.

Resolution direction: first-class constructs for the cases that genuinely need pointer-like data (e.g. chunk-managed buffers). Not yet designed. The legality rule should be stated explicitly regardless.

Mechanism sketched: eligibility is decided by taint propagation — an unbounded array taints the `value` containing it, and the taint propagates outward to disqualify any component holding it. This reuses the previous iteration's struct-tier inference wholesale, including the trick of storing the offending field path alongside the taint at declaration time, so reporting a failure does not require re-walking the type. [Load-time constant taint](Language%20Implementation.md#load-time-constant-taint) is the same mechanism and should share an implementation.

Re-evaluating array/cardinality syntax (Jose) belongs here: the syntax is what makes the unsafe form the easy one.

**Memory tiers, handle validity, and null/absence semantics** · `pending` · `4`

Carried over from an earlier design layer, not yet reconciled with the current constructs.

Frame-tier memory — bump-allocated, discarded at frame end — is the one tier with worked-out reasoning; it is what would make [GroupBy](#queries-and-predicates) technically safe.

Null coalescing operator (Jose) depends on absence semantics being settled first.

**Ownership and `non_serialized` have layout consequences** · `pending` · `4`

Both partition storage: a chunk cannot be blind-copied in a single direction if ownership varies within it, and a non-serialized component cannot share a chunk with synced data. The engine is expected to organize memory so layout matches these constraints — the same mechanism that will cover streaming/partial loads and interest management.

Open at the language level: how ownership is expressed. Expressing it structurally (a tag or relationship rather than a field) would let archetype partitioning segregate owned from remote entities automatically, and keep it a free presence check in `with`.

Mechanism side is tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

---

## Systems, Scheduling and Parallelism

**Systems as a first-class construct, and dependency declaration** · `pending` · `5`

System scheduling and dependency declaration are unspecified. Related and unresolved: whether **systems become a first-class construct**. They were previously judged unnecessary — a query bound to a trigger already covers what a system does — but expressing dependencies may require a named, addressable thing to hang them on, and anonymous self-driving queries give nothing to reference. Raised in conversation with a colleague; not previously written down anywhere.

Note the doc is currently inconsistent on this: [ECS focused](Design%20Principles.md#ecs-focused) lists systems among the primitives the design is organized around, while the language has no system construct at all.

**Static access-set extraction** · `pending` · `5`

The previous design required explicit per-query read/write declarations, on the grounds that "conflict detection requires declared, not inferred, access sets". The current position is the opposite and is settled: no author-declared access, with the compiler statically extracting per-field read/write sets from imperative bodies.

What remains open is the analysis pass itself — it is what makes parallelism a safe hint rather than an unchecked claim, and it is assumed everywhere and specified nowhere.

**`parallel`** · `idea` · `2`

Highly speculative, and it is not the real design — it sits on top of one that does not exist yet.

The intended model is that the engine builds a DAG from declared dependencies plus whatever parallelization opportunities it can infer, and executes scripts in that order. A `parallel` annotation might end up as one knob the author has over that behaviour, or might not exist at all. Too early to tell.

---

## Data Modeling and Declaration Syntax

**Field declaration syntax** · `pending` · `4`

Unspecified. Reordering declarations so the name is sandwiched between type and annotations (Jose), and optional fields with the associated bit-packing idea (Jose), are both proposals against this.

**`=` for both declaration and reassignment is a pit-of-failure case** · `discrepancy` · `4`

[Declaration and assignment](Language%20Spec.md#declaration-and-assignment) fixes a name's type at first use in a scope; every later use reassigns. A misspelled name therefore declares a new variable with an inferred type instead of raising an error. To revisit alongside field declaration syntax above.

**Generics and trait/conformance syntax** · `pending` · `3`

**`requires` on components** · `mechanism` · `2`

An alternative to inheritance: a component declares a dependency on another. Cascade-removal reuses the existing end-of-frame flush pass, the same mechanism as relationship deletion — reuse, not new machinery. No syntax, no semantics for conflicts or diamond cases.

**Value constants** · `pending` · `2`

Values like `Vector3.left`. Used in [LoomScript Examples](LoomScript%20Examples.md), unspecified in the language.

---

## Queries and Predicates

**The documented `with`/`where` boundary is not the one that costs** · `discrepancy` · `4`

[Clauses](Language%20Spec.md#clauses) presents the split in cost terms (fixed presence/bitmap check vs. per-entity runtime evaluation) and then disclaims that it constrains the compiler at all. Both are correct under the intended model: `with` and `where` together form one declarative matching region the compiler may reorder and optimize freely — for instance, servicing a `distance(...)` predicate from a spatial partition rather than per entity. `do` is a freeform imperative block and is largely opaque to that optimization.

The load-bearing boundary is therefore `where` vs. `do`, and the spec does not mention it. An author who hoists a predicate out of `where` into an early exit at the top of `do` — a refactor that looks purely cosmetic — silently forfeits acceleration and converts a partition lookup into a full scan. That is an implicit cost of exactly the kind the design forbids.

A second cost cliff sits inside `where`. If acceleration depends on the compiler recognizing specific predicate shapes, then predicates that match a known form are cheap and equivalent-but-unrecognized ones degrade to per-entity scans, with nothing in the syntax distinguishing them. Either the recognized set is specified, or `where` needs a restricted grammar. The recognized set and its acceleration structures are tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

Spatial partitioning for `distance(...)` is a candidate to evaluate against [No general indexing or materialization](Design%20Principles.md#no-general-indexing-or-materialization), not a violation of it.

**Incrementally maintained reductions** · `pending` · `2`

Whether `sum`/`count` reductions over a live query can be maintained incrementally (updated on write rather than rescanned on read) — would require exposing the prior value on a `changed` event, which is not yet designed. Mechanism sketched: hook the existing dirty-bitmap/version-per-block change detection and update a running accumulator on write, rather than building new infrastructure.

Deferred rather than solved: access to previous values is a requirement on the ECS design itself, and belongs in the requirement list gathered when that design happens, not here.

**GroupBy** · `shelved` · `1`

Ruled out of the query language, but worth recording why the ruling might not hold. The objection that killed it was that materialized results reopen the heap-in-component hazard — and that objection does not apply if the result is scoped to frame-tier memory: bump-allocated, discarded at frame end, never touching a component. A transient, non-addressable GroupBy is therefore technically safe. It was rejected on the honest-costing bar instead — it did not clearly earn its cost — which is a design-taste call, not an architectural blocker. Revisit if a real use case appears.

---

## Relationships

**Payload storage on symmetric relationships** · `pending` · `3`

Storage location for payload data on symmetric or many-to-many relationships, which have no single owning side.

**Quantified negation over a relationship or sub-match** · `pending` · `3`

"No entity related to this one satisfies X" — identified as a real gap, no syntax chosen.

**Transitive traversal** · `mechanism` · `3`

Needs a real graph walk, and is the one query construct whose cost is genuinely runtime-dependent rather than bounded by the match set. No depth bound decided; see [bounded execution](#errors-and-control-flow). Listed as a TODO in the spec's [Relationships](Language%20Spec.md#relationships) section.

**Ephemeral and exclusive relationships** · `pending` · `2`

Listed as a TODO in the spec's [Relationships](Language%20Spec.md#relationships) section, undesigned.

**Direct iteration over a bound relationship's targets** · `pending` · `2`

Syntax for iterating a relationship outside a query (e.g. given a held `Entity`, iterating its `Children`) — sketched as reusing the existing `for ... in` loop form, not finalized.

**Wildcard / `any` relationship terms** · `mechanism` · `2`

Compile to presence-only bitmap checks with no target materialization — the cheapest possible form, and a distinct codegen path from the named-target case. Named-target terms compile to forward relationship lookups, O(1) per match: a direct index or pointer chase on the source entity's relationship data, not a general join algorithm. Named targets that are never used can be optimized away by static analysis.

---

## Events and Change Detection

**Custom event declaration** · `pending` · `4`

Declaration syntax for custom, game-level events (e.g. `player_joined`) beyond the built-in `tick` / `changed` / `load` triggers. Binding a parameterized event to a query/proc without the trigger's parameter colliding with a `with`-bound name (e.g. `on dead(unit)` alongside a `with`-bound `unit`) is parked pending this.

**`changed(Component)` has no defined meaning on a non-owning peer** · `discrepancy` · `4`

Remote state arrives as a raw chunk write rather than a script-initiated mutation. If the engine diffs received chunks and fires `changed`, that is a recurring per-frame cost, against the no-implicit-costs principle. If it does not fire, reactive gameplay code behaves differently on owning and remote peers, which is precisely the networking awareness the design aims to remove. Unresolved; the language cannot stay silent, as `changed` is author-visible.

Mechanism side is tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

---

## Errors and Control Flow

**Bounded execution** · `contradiction` · `3`

Unreconciled, and newly reopened. The previous design flagged loop and recursion limits for determinism as needed but undesigned, noting there is no GC pause to blame instead. Transitive relationship traversal is the first construct with genuinely runtime-dependent cost and has no max-depth safeguard, which makes the gap concrete rather than theoretical.

**Error propagation and catching** · `idea` · `2`

The spec has `fail` and `assert` ([Error Handling](Language%20Spec.md#error-handling)); propagation and recovery are unspecified. Proposed (Jose): proc calls automatically propagate failures upwards, with some keyword to catch them. Must be weighed against [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient).

**No early-exit form inside `do`** · `pending` · `2`

Unspecified. Interacts with the `where`/`do` boundary above — an early exit is the refactor that silently forfeits acceleration.

**Alternative ternary syntax** · `idea` · `1`

With the condition first (Jose).

---

## Compilation and Backend

**Load-time branch elimination is an optimization, not a guarantee** · `discrepancy` · `2`

Deliberate — evaluating the condition at run time is equally correct, so promising elimination would over-constrain the backend. But it leaves an author with no language-level assurance that a branch behind an absent module costs nothing, which is the shape of implicit cost [No hidden control flow, no implicit costs](Design%20Principles.md#no-hidden-control-flow-no-implicit-costs) rules out.

Resolution direction: tooling rather than spec — surface what was stripped and what survived, per [Show the machinery in motion](Design%20Principles.md#show-the-machinery-in-motion). A guarantee stated in the language would buy the same confidence at the cost of pinning the backend.

**Load-time codegen** · `shelved` · `1`

Folding load-time-known values into native code during the Wasm-to-native step at load, rather than emitting indirection for them. Would make any load-time-resolved constant free at run time instead of costing a lookup. Not needed while the only load-time fact is module presence, since a presence check is a branch rather than a value feeding computation. Becomes relevant the moment a load-time value participates in layout.

**Load-time checking of dependency versions** · `shelved` · `1`

Allowing a manifest to admit a *range* of versions per dependency, with guards (`module.version >= 2`) selecting between implementations. The rule that makes it sound: unguarded code type-checks against the range's **floor**, and guards narrow only *upward*. Writes check against the floor, reads against the ceiling, so both stay statically decidable without enumerating configurations. Deferred because a single declared version per dependency removes the problem entirely, and version skew is a mod-ecosystem concern that will be designed better against real modules than in the abstract.

**Virtualized data layouts** · `shelved` · `1`

Scripts addressing fields through a layout table populated at load, rather than baking static offsets. Would let a type's size or field widths vary per deployment while keeping one portable artifact. Rejected for now on the honest-costing bar: it puts an indirection on every field access to buy configuration flexibility that [Scripts are portable](Design%20Principles.md#scripts-are-portable) says the engine should be absorbing instead.

Related and dropped outright rather than deferred: **two-tier compilation** (mods compiled once and portably, internal modules compiled per target). It resolves the same tension, but by giving up the single-artifact guarantee, and it splits the backend into two paths where the less-tested one is the one shipped to third parties.

---

## Spec Consistency

**`LoomScript Examples.md` and the spec disagree** · `contradiction` · `2`

Partly aspirational syntax, partly spec lag; each divergence needs resolving in one direction. Current list:

- `Vector3.left` — see [value constants](#data-modeling-and-declaration-syntax).
- `create entity with (...)` uses parentheses; [Creation](Language%20Spec.md#creation) omits them.
- `for entity with Position, Velocity do` — no parentheses around the binding, unlike every example in [Queries](Language%20Spec.md#queries).
- `entity.position.value` — lowercase field access against a `Position` component; casing convention for component access is unstated.
