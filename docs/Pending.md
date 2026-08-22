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

Undecided, needs its own design pass. The constraints any answer must satisfy are in [Engine Core](Engine%20Core.md#constraints). The two live candidates:

- *Archetype/table storage.* Entities are grouped by component set and stored contiguously. Hazard: structural changes move the entity in memory, invalidating handles. Deferring removal does not fix this, because adds relocate too — so it fails the handle-stability constraint as stated.
- *Inverted hierarchical bitmap storage.* Each component owns a bitmap over entity slots; entities never move, which satisfies handle stability structurally. Empty bitmap blocks do not materialize storage, so the memory cost depends on entity-ID clustering rather than on the architecture.

The ownership entry below presumes archetype partitioning, which it has not earned.

This is the root blocker for the rest of this section, for `changed` on a non-owning peer, and for handle-validity semantics — whether a handle can be invalidated by an unrelated entity's mutation is a property of the storage model, not of the handle.

**Entity identity and generation** · `pending` · `4`

Unspecified. How an entity ID is composed, whether it carries a generation counter, and what a stale ID resolves to. Blocked on the storage model.

**Copy granularity** · `pending` · `3`

Whether the unit of transfer between peers is the memory block, a sub-range, or a single component is unexamined. Interacts directly with the storage decision.

**The synchronization path** · `pending` · `3`

Memory block selection, delta compression and peer topology are unwritten. [Frame Model and Synchronization](Engine%20Core.md#frame-model-and-synchronization) records only the premise the rest of the design leans on: per-frame chunk copies, with a peer either owning entities or receiving them. That premise is what `non_serialized`, bit packing and the flat-copyable rule are all written against.

**Storage for pointer-like component data** · `pending` · `3`

ECS-managed buffers — the storage `dynamic` selects — have no design. Related to addressability below.

**Addressability of a `dynamic` component field** · `pending` · `3`

The field legality rule itself is now written up — [the flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) at the engine level, [Storage](Language%20Spec.md#storage) at the language level, [Nested dynamic data in components](#storage-and-memory-layout) for the option it forecloses.

What that write-up does not settle: whether a `dynamic` component field is directly addressable or handle-like. Holding a reference to one across a frame boundary is the case that would bite, which makes this the same question as handle validity below, asked of engine-managed memory rather than of an entity.

**Nested dynamic data in components** · `idea` · `2`

Option deliberately not taken, recorded because it is a strict superset of the rule above — nothing written under the current rule becomes illegal if this is adopted later.

The idea: exploit components' flat layout, and design a single pointer representation that discriminates ECS-managed memory from general memory while occupying the same space. Dynamic data could then nest at any depth rather than only at a component's top level.

Two things make it hard:

- **The discriminant cannot be dynamic.** A block-relative offset survives being blind-copied to a peer; a general-memory pointer does not. If the mode were decided at run time, validity of a copy would depend on runtime state, leaving only a per-pointer check at sync time (a recurring per-frame cost) or silent corruption in networked builds. So the mode must be static — decided by where the field lives.
- **That reintroduces two layouts per `value`**, now identical in size but different in meaning. Copying a stack-side value into a component field stops being a copy and becomes a deep copy plus pointer fixup, at a cost proportional to the value's dynamic content. Coherent only if promotion into a component is an explicit named operation, never a silent assignment — which is where the previous iteration independently landed ([Previous Iteration.md:34](Previous%20Iteration.md)).

Blocked on the storage model regardless: "block-relative" presumes archetype storage. Under inverted-bitmap storage entities never move and the per-component arrays are the storage, so there may be no block to be relative to in the same sense.

**Flattened component layout** · `mechanism` · `3`

Components have a fixed layout, so nested `value` fields resolve to static offsets rather than requiring navigation. Worth stating as its own mechanism because several open items lean on it:

- Static access-set extraction gets nested-field granularity for free — `Nameplate.title.text` is an offset and a width, not a load-and-chase.
- `where` predicates can address nested fields at the same cost as top-level ones.
- It settles that `value` nesting costs nothing at run time, which is what makes values a free abstraction rather than a structural choice.
- The taint mechanism already carries a field path; flattening turns that path into the offset.

**Memory tiers, handle validity, and null/absence semantics** · `pending` · `4`

Carried over from an earlier design layer, not yet reconciled with the current constructs.

The previous iteration's answer to absence is the handle state enum described under [Asynchronous operations](#storage-and-memory-layout) — `Pending` / `Ready` / `Failed` / `Dead`, with `.is_valid()` true only for `Ready`. There is no null and no separate `Result` type; absence, failure and pending completion are the same three-valued question asked of a handle.

Frame-tier memory — bump-allocated, discarded at frame end — is the one tier with worked-out reasoning; it is what would make [GroupBy](#queries-and-predicates) technically safe.

Null coalescing operator (Jose) depends on absence semantics being settled first.

**Asynchronous operations** · `pending` · `4`

Nothing in the current spec addresses operations that do not complete within the frame they were requested — resource and asset loading being the obvious case. Direction from [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#handles--validity): the request returns a handle immediately, and the handle's state enum (`Pending` / `Ready` / `Failed` / `Dead`) is the completion signal. No futures, no callbacks, no suspension — the author polls or matches on state.

No new machinery is required: handle state is an ordinary [enum](Language%20Spec.md#enums), and `match` already binds label payloads, so the polling form falls out of constructs the spec has.

What remains a decision is that handle state carries three jobs at once — absence, fallibility, and async completion. It also means the language has no `Result` type and never needs one, which is a position the current spec has not taken.

Depends on the host embedding API, which is unwritten — see [Runtime & Deployment](Runtime%20&%20Deployment.md#not-yet-written).

**Ownership and `non_serialized` have layout consequences** · `pending` · `4`

Both partition storage: a block cannot be blind-copied in a single direction if ownership varies within it, and a non-serialized component cannot share a block with synced data. The engine is expected to organize memory so layout matches these constraints — the same mechanism that will cover streaming/partial loads and interest management.

Open at the language level: how ownership is expressed. Expressing it structurally (a tag or relationship rather than a field) would let archetype partitioning segregate owned from remote entities automatically, and keep it a free presence check in `with`.

Mechanism side is tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

---

## Systems, Scheduling and Parallelism

**Systems as a first-class construct, and dependency declaration** · `pending` · `5`

System scheduling and dependency declaration are unspecified. Related and unresolved: whether **systems become a first-class construct**. They were previously judged unnecessary — a query bound to a trigger already covers what a system does — but expressing dependencies may require a named, addressable thing to hang them on, and anonymous self-driving queries give nothing to reference. Raised in conversation with a colleague; not previously written down anywhere.

Note the doc is currently inconsistent on this: [ECS focused](Design%20Principles.md#ecs-focused) lists systems among the primitives the design is organized around, while the language has no system construct at all. Accepted for now. Whichever way this lands, that principle has to be settled with it — reworded if systems become first-class, with the primitive struck from the list if they do not.

Direction settled: a system is an organization and scheduling construct, not a behaviour container. Two pieces of the previous iteration's design ([Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#queries--systems)) are superseded and should not be carried over — `run_query`, made redundant by named queries already being invocable like procedures, and the overridable `tick()` method, replaced by an `on tick` binding. What survives is the shape: a zero-argument block the engine instantiates and script never constructs.

Still to design: how dependencies are declared, whether ordering within a system is positional or explicit, and whether a system is the thing dependencies attach to or merely a namespace.

**Static access-set extraction** · `pending` · `5`

The previous design required explicit per-query read/write declarations, on the grounds that "conflict detection requires declared, not inferred, access sets". The current position is the opposite and is settled: no author-declared access, with the compiler statically extracting per-field read/write sets from imperative bodies.

What remains open is the analysis pass itself — it is what makes parallelism a safe hint rather than an unchecked claim, and it is assumed everywhere and specified nowhere.

**Inferred procedure purity** · `idea` · `3`

A procedure's purity is derived by the compiler from the same analysis that extracts access sets: a proc that writes no ECS data and calls no impure proc is pure. Nothing is declared, so the common case carries no signature noise, which is the cost Verse pays for its `<computes>`/`<reads>`/`<writes>` effect specifiers and the reason its "learnable as a first language" goal is in tension with its own effect system.

An optional annotation would let an author pin the intent, so a proc meant to stay pure fails compilation when a later edit makes it impure, rather than silently reclassifying.

Two use sites motivate it. First, `where` currently guarantees no mutation only by position: the guarantee holds at the clause boundary and evaporates at a call boundary, since nothing in the spec says whether a proc invoked from `where` may write. Purity is the property that closes it. Second, calling a pure proc as a freestanding statement is dead code, and can be rejected the same way [Statements and Expressions](Language%20Spec.md#statements-and-expressions) already rejects a bare expression that discards its result.

**`parallel`** · `idea` · `2`

Highly speculative, and it is not the real design — it sits on top of one that does not exist yet.

The intended model is that the engine builds a DAG from declared dependencies plus whatever parallelization opportunities it can infer, and executes scripts in that order. A `parallel` annotation might end up as one knob the author has over that behaviour, or might not exist at all. Too early to tell.

---

## Data Modeling and Declaration Syntax

**Declaration syntax pass** · `pending` · `4`

Direction settled: declaration becomes explicit, so a bare `=` is always reassignment and a misspelled name is an error rather than a silent new binding. This closes the pit-of-failure in [Declaration and assignment](Language%20Spec.md#declaration-and-assignment), which currently fixes a name's type at first use and treats every later use as reassignment.

Exact form deferred to a dedicated pass. Open within it:

- Marker for the inferred case. A leading type is already an unambiguous declaration (`integer y = 0`); only inference lacks one. `x := 5` needs no keyword but is punctuation, against [Readable by non-engineers](Design%20Principles.md#readable-by-non-engineers); `var x = 5` reads better but adds a second declaration form beside the type-first one.
- Type-first (`integer x`) versus name-first (`x: f32`, previous iteration).
- Whether file-level mutable state exists and takes a distinct keyword. It is game-tier — it survives frames, and hot reload has to decide what happens to it — so making that visible at the declaration is worth considering.
- Reordering so the name sits between type and annotations (Jose). Possibly already satisfied: `integer ammo range(0..999)` puts it there.
- Optional fields and the associated bit-packing idea (Jose).

**Procedure overloading — decided, not yet written into the spec** · `pending` · `3`

- Procs overload on argument types. Parameter names do not participate, so `damage(amount: integer)` and `damage(percent: integer)` are not a valid overload set.
- Types and procs cannot share a name; overloading lives inside the proc namespace only. Otherwise `Health(current: 100)` is ambiguous between construction and a call.
- Constrained numerics are one type for resolution. `integer range(0..100)` and `integer` do not form an overload set — constraints refine representation, not identity.
- `integer` implicitly converts to `decimal`; the non-converted candidate wins. Under [unified numeric representation](Language%20Implementation.md#unified-representation) this generalizes to "prefer the smaller scale change".

Combined with dot-sugar on the first parameter, overloading covers the plain "one name, many types" case, so traits are needed only for generic code.

Open: the syntax doc's rule that a hand-written concrete generic query takes precedence over the autogenerated one is a specialization rule, and needs reconciling with these when generics are designed.

**Casing convention — decided, not yet written into the spec** · `pending` · `3`

PascalCase names types — values, components, tags, relationships, enums. snake_case names everything else — procs, fields, locals, parameters. Casing is convention rather than a compiler rule; what actually prevents collisions is that a proc may not take a type's name.

Component access on an entity keeps the type's own casing, since it names a type rather than a field:

```
e.Health.current          // one lookup, one offset
e.Position.value.x        // one lookup, two offsets
```

Two reasons. It is the same symbol written in `with Health`, `create entity with Health(...)` and `if e has Health`, so lowercasing it only in access position makes one symbol change case by context. And it marks where the cost is: component access is a keyed lookup that can miss and halt, while field access is a static offset under [flattened component layout](#storage-and-memory-layout).

The invariant that falls out: a well-formed access has exactly one PascalCase segment after the entity handle. Everything before it is a handle, everything after is free offsets. Two capitals in a chain would mean two lookups, and no construct produces that, so it reads as an error rather than a hidden cost.

Written into the spec. Still to fix: `entity.position.value` in [LoomScript Examples](LoomScript%20Examples.md).

**Expression statements — decided, not yet written into the spec** · `pending` · `2`

An expression statement is legal only when its top-level expression is a call, or a keyword whose effects are known (`create`, `delete`). Bare `Health(current: 100)`, `a + b` and `e.Health` are errors — dead code that looks like it does something.

`create` and `delete` are statement forms that optionally bind, not expressions that must. Dropping the handle from a creation is legitimate: the entity exists and queries will find it.

The previous iteration barred unbound construction on ownership grounds — the binding governs lifetime, so construction without a destination is invalid. That argument does not apply here, since values are copied and own no memory. Same rule, different justification, and the new one is why the general form is preferable to a construction-specific one.

**Parens carry three roles — accepted** · `pending` · `1`

Field lists, construction and calls all use `()`. The previous iteration split them (`{}` for construction, `()` for calls) to avoid ambiguity when a type and a proc share a name. Not adopted: `define` marks declarations, and no overloading across the type and proc namespaces means resolution is unambiguous without a second bracket form. Recorded so the divergence from the previous iteration is deliberate.

**Generics and trait/conformance syntax** · `pending` · `3`

Sketched in [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#generics--traits), never carried forward. Generics resolve by monomorphization, with `<>` holding any compile-time parameter — type parameters and size parameters alike — and no marker needed, since types are never values and no ambiguity exists to guard against.

Traits declare **fields only**, never procedures. A field is satisfied three ways: a same-named, same-typed field (empty `trait X for Y { }` body); a differently-named field, by alias; or a getter/setter pair. Conformance is always explicit and never structural, including for types the author does not own, primitives included. No access modifiers on trait fields — read/write is the using system's decision, never dictated by the data.

Two things to reconcile when this is taken up:

- Proc-backed trait fields break the assumption that field access is a plain read or write, which [static access-set extraction](#systems-scheduling-and-parallelism) and [flattened component layout](#storage-and-memory-layout) both rely on.
- A hand-written concrete generic query taking precedence over the autogenerated one is a specialization rule, and needs squaring with the overload rules above.

**Components as a single type** · `idea` · `3`

From [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#components--lifetime-tiers): no separate handle type ever appears in the type system. The compiler switches a component's backing between stack bytes and entity storage based on what it can prove, and the author sees one type and one operation set throughout. Assignment always copies; behaviour differs by what is copied, never by a hidden type distinction. Query bindings are live-backed by construction.

Worth evaluating against [Domain over technicism](Design%20Principles.md#domain-over-technicism) — it is the same idea applied to handles. The cost is that whether a write lands on entity data or on a local becomes a fact about provenance rather than about the type, which is exactly the kind of thing [No hidden control flow, no implicit costs](Design%20Principles.md#no-hidden-control-flow-no-implicit-costs) is suspicious of.

**Procedure restrictions** · `pending` · `2`

[Procedures](Language%20Spec.md#procedures) states there are no lambdas or closures. Three further restrictions from the previous iteration are unstated: procedures cannot be stored in components, cannot be held in persistent state, and cannot be used as callbacks. Also unstated is dot-sugar on the first parameter — `effect.get_magnitude()` for `get_magnitude(effect)` — which the overload rules above assume exists.

**`requires` on components** · `mechanism` · `2`

An alternative to inheritance: a component declares a dependency on another. Cascade-removal reuses the existing end-of-frame flush pass, the same mechanism as relationship deletion — reuse, not new machinery. No syntax, no semantics for conflicts or diamond cases.

**Bit packing** · `idea` · `2`

Three directions to explore, not necessarily together:

- Automatic packing of declared booleans within a type.
- A dedicated bitfield primitive.
- Flag enums — power-of-two labels with set operations, against the current rule that a label's value comes from declaration order.

Runs into the alignment rule in [Numeric Representation](Language%20Implementation.md#numeric-representation): numbers are byte-aligned, trading storage efficiency for direct addressability. Packed fields are not directly addressable, so any of these needs a story for how a packed field is read, written and named in an access set. Jose's optional-fields proposal in the declaration syntax pass carries the same idea from a different direction.

**Tuples** · `pending` · `3`

[Tuples](Language%20Spec.md#tuples) exist only as the return type of a multi-value proc. Whether they are a general type — declarable, storable in a component, bindable — is unspecified. A storable tuple would need a position under the flat-copyable rule.

**Value constants** · `pending` · `2`

Values like `Vector3.left`. Used in [LoomScript Examples](LoomScript%20Examples.md), unspecified in the language.

---

## Queries and Predicates

**The documented `with`/`where` boundary is not the one that costs** · `discrepancy` · `4`

[Clauses](Language%20Spec.md#clauses) presents the split in cost terms (fixed presence/bitmap check vs. per-entity runtime evaluation) and then disclaims that it constrains the compiler at all. Both are correct under the intended model: `with` and `where` together form one declarative matching region the compiler may reorder and optimize freely — for instance, servicing a `distance(...)` predicate from a spatial partition rather than per entity. `do` is a freeform imperative block and is largely opaque to that optimization.

The load-bearing boundary is therefore `where` vs. `do`, and the spec does not mention it. An author who hoists a predicate out of `where` into an early exit at the top of `do` — a refactor that looks purely cosmetic — silently forfeits acceleration and converts a partition lookup into a full scan. That is an implicit cost of exactly the kind the design forbids.

A second cost cliff sits inside `where`. If acceleration depends on the compiler recognizing specific predicate shapes, then predicates that match a known form are cheap and equivalent-but-unrecognized ones degrade to per-entity scans, with nothing in the syntax distinguishing them. Either the recognized set is specified, or `where` needs a restricted grammar. The recognized set and its acceleration structures are tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

Spatial partitioning for `distance(...)` is a candidate to evaluate against [No general indexing or materialization](Design%20Principles.md#no-general-indexing-or-materialization), not a violation of it.

** Reductions ** 

Reductions have been pulled from the spec for now, they need further work.

Putting the entire text here for reference: 

### Reductions

 Reductions are special kinds of queries that produce a single value instead of iterating over all results imperatively.
 A query ending by a reducer instead of a `do` block becomes a value-producing queries usable anywhere a value is expected:
 
```
define query count_dead_units 
for unit with Unit, without Alive
count unit

var dead = count_dead_units()
```
 
`count` and structural/relationship-cardinality reductions cost no
additional scan. `sum`/`avg` over a field, and `max_by`/`min_by`, require visiting
every matching entity and cost the same as an equivalent hand-written
scan — the language does not disguise this cost as free.
 
There is no general materialized or orderable result-set type. Grouping,
sorting, and top-N selection are intentionally outside the query language;
where needed, they are written as ordinary iteration inside a `proc`.
 

**Incrementally maintained reductions** · `pending` · `2`

Whether `sum`/`count` reductions over a live query can be maintained incrementally (updated on write rather than rescanned on read) — would require exposing the prior value on a `changed` event, which is not yet designed. Mechanism sketched: hook the existing dirty-bitmap/version-per-block change detection and update a running accumulator on write, rather than building new infrastructure.

Deferred rather than solved: access to previous values is a requirement on the ECS design itself, and belongs in the requirement list gathered when that design happens, not here.

**Query amortization and update rates** · `pending` · `3`

Budgeted "process N per tick, resume next tick where it left off" work. Reasoning from [Previous Iteration](Previous%20Iteration.md), never carried forward: true coroutines are disallowed, since suspending mid-iteration holds call-stack state across a frame boundary and violates the tier rules. The replacement is a resumable cursor — position and accumulator stored as game-tier state, each resume starting a fresh call-stack scope.

Staggered update rates (e.g. distant entities every other frame) are treated separately and more simply, as bucketing: partition the query by `entity_id % K` and process one bucket per frame, with no suspension mechanism at all.

No syntax for either. Open whether the cursor is author-visible state or a query-level annotation.

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

**Change-tracking surface** · `pending` · `4`

[Change Tracking](Language%20Spec.md#change-tracking) states only that `changed(Component)` fires on the frame a matching component's value changes. Unspecified: granularity (component or field), what counts as a change when a write stores the same value, how it interacts with `with changed` in a `for` clause, and when the flag is cleared relative to system order.

**Custom event declaration** · `pending` · `4`

Declaration syntax for custom, game-level events (e.g. `player_joined`) beyond the built-in `tick` / `changed` / `load` triggers. Binding a parameterized event to a query/proc without the trigger's parameter colliding with a `with`-bound name (e.g. `on dead(unit)` alongside a `with`-bound `unit`) is parked pending this.

**`changed(Component)` has no defined meaning on a non-owning peer** · `discrepancy` · `4`

Remote state arrives as a raw chunk write rather than a script-initiated mutation. If the engine diffs received chunks and fires `changed`, that is a recurring per-frame cost, against the no-implicit-costs principle. If it does not fire, reactive gameplay code behaves differently on owning and remote peers, which is precisely the networking awareness the design aims to remove. Unresolved; the language cannot stay silent, as `changed` is author-visible.

Mechanism side is tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

---

## Errors and Control Flow

**Bounded execution** · `contradiction` · `3`

Unreconciled, and newly reopened. The previous design flagged loop and recursion limits for determinism as needed but undesigned, noting there is no GC pause to blame instead. Transitive relationship traversal is the first construct with genuinely runtime-dependent cost and has no max-depth safeguard, which makes the gap concrete rather than theoretical.

[Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#error-handling) does answer it, and cheaply: a simple runtime execution cap that halts on exceeding it, with no proof-of-termination requirement and no annotations. Worth adopting or rejecting explicitly rather than leaving the gap open.

**Halt unwind granularity** · `pending` · `3`

[Error Handling](Language%20Spec.md#error-handling) says `fail` halts script execution, but not how far the halt travels. The previous iteration specified it precisely: a halt unwinds to the nearest engine-called entry point. A tick function aborts the whole tick; a query callback aborts only that entity's iteration and the rest continue; a cursor resume aborts only that resume.

That granularity is what makes [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient) concrete. It also draws a line the current spec does not: expected absence (a dead handle, an unloaded resource, a missing optional component) is never a halt, and is handled through handle state instead.

The previous iteration kept the boundary unambiguous by forbidding a query from invoking another query. The current spec has named queries "manually invoked" ([Queries](Language%20Spec.md#queries)) and places no restriction on where from, so the question the ban avoided is live here. A halt inside a nested query has no defined stopping point: the inner query's current entity, the outer one's, or the whole trigger.

Naming: the previous iteration used `halt` rather than `fail`, on the grounds that it communicates only the current entry point stopping. The current spec uses `fail`.

**Error propagation and catching** · `idea` · `2`

The spec has `fail` and `assert` ([Error Handling](Language%20Spec.md#error-handling)); propagation and recovery are unspecified. Proposed (Jose): proc calls automatically propagate failures upwards, with some keyword to catch them. Must be weighed against [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient).

**Intrinsic fallibility** · `idea` · `4`

An alternative to the entry above, and a generalization of it. Failure becomes a property of an expression rather than a construct layered on top of calls. An operation the compiler knows can fail — component access on an entity that may not have it, index out of bounds, division or modulo by zero, a dead handle, a relationship with no target, a value outside a declared range, a narrowing coercion — is *fallible*, and a fallible expression only type-checks inside a context that handles failure. `if` is that context; there is no catch keyword and no new syntax. The feature is subtraction.

Fallibility is inferred, by the same pass as [Inferred procedure purity](#systems-scheduling-and-parallelism). A proc containing an unguarded fallible expression is itself fallible, so calling it is itself a fallible expression. That gives Jose's upward propagation, but typed: propagation is real, and every frame in the chain opted in visibly at compile time rather than by an invisible unwinding path.

The line to hold is derived versus authored. Everything above is derived — the compiler knows the operation has a failure mode. `fail` and `assert` are authored, stay terminal, and are not catchable; if an invariant violation becomes recoverable, any caller can swallow it. This also settles the distinction [Halt unwind granularity](#errors-and-control-flow) needs, where expected absence is never a halt.

Declared ranges are what makes this affordable here and not in Verse. Verse forces a guard on every division because it knows nothing about the divisor; ranges are already stated in this language, so `a / b` is infallible when `b`'s range excludes zero, and arithmetic is infallible when the result's range fits the target. Overflow stops being a separate concept — it is a result that does not fit the target's range. The ergonomic consequence inverts in the language's favour: a required guard is a signal that the author under-specified the domain, so the remedy is to state the range, which is [Domain over technicism](Design%20Principles.md#domain-over-technicism) exactly.

It also collapses `has`. A fallible expression in `where` means the entity is filtered out, so structural presence and value predicates become one rule and `with` is its accelerable form. Open: filtered-because-absent and filtered-because-false become indistinguishable, which is a silent-skip path to accept or reject deliberately.

Costs. Range arithmetic becomes load-bearing type checking rather than metadata — interval propagation through the arithmetic operators, decidable at the load boundary, and specified, since an equivalent-but-unrecognized range expression degrading to fallible is the same cost cliff as the `where` predicate-shape problem above. An infallible escape is needed where refinement cannot prove safety — saturating or wrapping operators, explicit at the call site, with fallible as the default. Viability is entirely a function of how strong the range analysis is: with weak refinement, guards proliferate and [Readable by non-engineers](Design%20Principles.md#readable-by-non-engineers) is lost, so this is not adoptable independently of that analysis. Runtime cost is a branch the author wrote, with no unwinding machinery, which suits the AOT and interpreter targets. Still to decide: that nothing binds on failure, including multi-return tuples; and the interaction with **Implicit transactional mutation** below, since a fallible proc that wrote before failing leaves partial mutation unless the write buffer is scoped to the fallible call.

**Implicit transactional mutation** · `idea` · `3`

Raised as a counterpart to Verse's `<transacts>` rollback, but arrived at from the opposite direction: Verse needs an author-declared effect and a general transactional memory, whereas the compiler here already sees every write to ECS data (see [Static access-set extraction](#systems-scheduling-and-parallelism)). If every mutation in a scope is known statically, the scope's writes can be buffered and applied atomically on successful exit, with structural changes deferred to a frame boundary.

Two properties would follow. A halt would leave no partially mutated world, which is what makes [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient) a real guarantee rather than a best effort, and it directly affects what **Halt unwind granularity** above has to specify. Deferred structural change also removes the mid-iteration invalidation hazard that handle stability currently has to absorb.

Open, and not obviously affordable. Buffering writes is a copy and a commit pass that the author did not ask for, which is exactly the shape [No hidden control flow, no implicit costs](Design%20Principles.md#no-hidden-control-flow-no-implicit-costs) forbids, so the analysis has to establish that the buffer is bounded and statically sized before this can be considered. Also unresolved: whether the transactional scope is the query body, one entity's iteration, or the trigger; and whether reads within a scope observe its own uncommitted writes.

**No early-exit form inside `do`** · `pending` · `2`

Unspecified. Interacts with the `where`/`do` boundary above — an early exit is the refactor that silently forfeits acceleration.

**Alternative ternary syntax** · `idea` · `1`

With the condition first (Jose).

---

## Compilation and Backend

**Width-specialized computation** · `idea` · `2`

[Computation](Language%20Implementation.md#computation) expands operands to 64 bits. Generating variants of math primitives and procs against the widths actually used would cut that, but it is exclusively a performance improvement — the naive path must be correct on its own.

**Host embedding API** · `pending` · `5`

What the engine exposes to guest modules and how capabilities are granted is unwritten. Blocks [asynchronous operations](#storage-and-memory-layout) and the whole I/O surface below.

**Reload semantics for live state** · `pending` · `4`

[Hot reload](Runtime%20&%20Deployment.md#hot-reload) swaps a module's Wasm object, but what happens to entities and component data whose defining module is being swapped is undefined. Interacts with file-level mutable state, if it exists — see [Declaration syntax pass](#data-modeling-and-declaration-syntax).

**Observable agreement between backends** · `pending` · `3`

Whether AOT and interpreted backends must agree observably — execution bounds, numeric edge cases — or may differ. Fixed-point arithmetic removes most of the float divergence risk, but bounded execution (see [Errors and Control Flow](#errors-and-control-flow)) is decided per backend unless this is pinned.

**I/O surface** · `pending` · `3`

Input, audio, asset loading, save files, network transport. Not excluded by the design, simply unspecified as host-exposed capabilities. Blocked on the host embedding API.

**Load-time branch elimination is an optimization, not a guarantee** · `discrepancy` · `2`

Deliberate — evaluating the condition at run time is equally correct, so promising elimination would over-constrain the backend. But it leaves an author with no language-level assurance that a branch behind an absent module costs nothing, which is the shape of implicit cost [No hidden control flow, no implicit costs](Design%20Principles.md#no-hidden-control-flow-no-implicit-costs) rules out.

Resolution direction: tooling rather than spec — surface what was stripped and what survived, per [Show the machinery in motion](Design%20Principles.md#show-the-machinery-in-motion). A guarantee stated in the language would buy the same confidence at the cost of pinning the backend.

**Const-eval of pure procedures** · `idea` · `2`

[Constants](Language%20Spec.md#constants) binds a name to an expression built from literals and other constants, so any value that needs computation cannot be a constant and has to be hand-computed into a magic number. Verse's "just one language" principle is the opposite position — the same constructs run at compile time and run time — and the cheap version of it applies here: once purity is inferred ([Inferred procedure purity](#systems-scheduling-and-parallelism)), a pure proc called with constant arguments is itself a constant, and the load-time evaluator needed for load-time conditionals already exists. Derived constants — lookup tables, precomputed curves, a size from a formula — become expressible without a separate mechanism.

Same inference-plus-optional-annotation shape as purity. Const-eval is implicit wherever the arguments are constant, so the common case carries no ceremony; an optional annotation pins the intent, so a binding meant to be resolved at load time fails compilation if a later edit makes it runtime-dependent rather than silently becoming a per-execution computation.

Open: interaction with the existing rule that constants depending on a load-time conditional cannot determine data layout, since a const-eval'd proc widens what can reach an array bound or range annotation; and termination, since a const-eval'd call must complete at the load boundary, which ties it to **Bounded execution** above.

**Bundled source produces private types** · `pending` · `1`

From the previous iteration: sharing source between modules by local bundling, without registering a module, yields a distinct private type per bundler — by design, not as a defect. Sharing a real type requires a proper module dependency. Unstated in [Program Structure](Language%20Spec.md#program-structure), and the kind of rule that is discovered the hard way if left implicit.

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

Examples now follow the spec. Most of the earlier list turned out to be spec lag rather than aspirational syntax: parentheses are optional wherever a construct reads unambiguously without them, so the examples were already idiomatic and the spec was missing the rule. Component access casing was the one real fix.

Still divergent, because the spec has no position to sync to:

- `Vector3.left` — see [value constants](#data-modeling-and-declaration-syntax).

**Range violation: which build halts where** · `pending` · `3`

Settled and written into [Ranges](Language%20Spec.md#ranges): never wrap, halt on out-of-range writes, clamp only via explicit syntax. What is not settled is which range is enforced in which build:

- *Debug halts over the exact declared range, release over the representable range.* Conventional, cheap in release, but the two builds are then different programs. A value outside `range(0..100)` but inside a signed byte survives in release and halts in debug.
- *Warn over the exact range, halt over the representable range, in all modes.* Build-independent.

The second is worth the weight it costs, because of networking. State is bulk-synchronized between peers, so a peer on a debug build and a peer on a release build diverging on the same input is a desync, not just a debugging inconvenience. Build-dependent halt behaviour makes the declared range an invariant in one build and a hint in the other.
