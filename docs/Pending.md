## Purpose

Everything known to be unresolved, organized by area. Recording an item here is not a commitment to the feature — several entries exist to preserve reasoning that has already been re-derived more than once.

**Type** 
- `pending` (known gap, no design yet) 
- `discrepancy` (the spec does not follow through on a stated design principle) 
- `contradiction` (positions that conflict, with the previous iteration or internally)
- `mechanism` (implementation reasoning worked out, but no syntax or semantics) 
- `idea` (raised, not committed) 

Items decided against move to [Shelved](Shelved.md), which mirrors this document's sections.

**Importance** rated 1–5 by how much other work the item blocks, not by how large it is.

**`syntax`** marks entries that put forward a concrete spelling that has not been decided.

---

## Storage and Memory Layout

### Storage model · `contradiction` · `5`

Undecided, needs its own design pass. The constraints any answer must satisfy are in [Engine Core](Engine%20Core.md#constraints). The two live candidates:

- *Archetype/table storage.* Entities are grouped by component set and stored contiguously. Hazard: structural changes move the entity in memory, invalidating handles. Deferring removal does not fix this, because adds relocate too — so it fails the handle-stability constraint as stated.
- *Inverted hierarchical bitmap storage.* Each component owns a bitmap over entity slots; entities never move, which satisfies handle stability structurally. Empty bitmap blocks do not materialize storage, so the memory cost depends on entity-ID clustering rather than on the architecture.

The ownership entry below presumes archetype partitioning, which it has not earned.

This is the root blocker for the rest of this section, for `changed` on a non-owning peer, and for handle-validity semantics — whether a handle can be invalidated by an unrelated entity's mutation is a property of the storage model, not of the handle.

### Entity identity and generation · `pending` · `4`

Unspecified. How an entity ID is composed, whether it carries a generation counter, and what a stale ID resolves to. Blocked on the storage model.

### Copy granularity · `pending` · `3`

Whether the unit of transfer between peers is the memory block, a sub-range, or a single component is unexamined. Interacts directly with the storage decision.

### The synchronization path · `pending` · `3`

Memory block selection, delta compression and peer topology are unwritten. [Frame Model and Synchronization](Engine%20Core.md#frame-model-and-synchronization) records only the premise the rest of the design leans on: per-frame chunk copies, with a peer either owning entities or receiving them. That premise is what `non_serialized`, bit packing and the flat-copyable rule are all written against.

### Storage for pointer-like component data · `pending` · `3`

ECS-managed buffers — the storage `dynamic` selects — have no design. Related to addressability below.

### Addressability of a `dynamic` component field · `pending` · `3`

The field legality rule itself is now written up — [the flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) at the engine level, [Storage](Language%20Spec.md#storage) at the language level, [Nested dynamic data in components](#storage-and-memory-layout) for the option it forecloses.

What that write-up does not settle: whether a `dynamic` component field is directly addressable or handle-like. Holding a reference to one across a frame boundary is the case that would bite, which makes this the same question as handle validity below, asked of engine-managed memory rather than of an entity.

### Nested dynamic data in components · `idea` · `2`

Option deliberately not taken, recorded because it is a strict superset of the rule above — nothing written under the current rule becomes illegal if this is adopted later.

The idea: exploit components' flat layout, and design a single pointer representation that discriminates ECS-managed memory from general memory while occupying the same space. Dynamic data could then nest at any depth rather than only at a component's top level.

Two things make it hard:

- **The discriminant cannot be dynamic.** A block-relative offset survives being blind-copied to a peer; a general-memory pointer does not. If the mode were decided at run time, validity of a copy would depend on runtime state, leaving only a per-pointer check at sync time (a recurring per-frame cost) or silent corruption in networked builds. So the mode must be static — decided by where the field lives.
- **That reintroduces two layouts per `value`**, now identical in size but different in meaning. Copying a stack-side value into a component field stops being a copy and becomes a deep copy plus pointer fixup, at a cost proportional to the value's dynamic content. Coherent only if promotion into a component is an explicit named operation, never a silent assignment — which is where the previous iteration independently landed ([Previous Iteration.md:34](Previous%20Iteration.md)).

Blocked on the storage model regardless: "block-relative" presumes archetype storage. Under inverted-bitmap storage entities never move and the per-component arrays are the storage, so there may be no block to be relative to in the same sense.

### Flattened component layout  · `mechanism` · `3`

Components have a fixed layout, so nested `value` fields resolve to static offsets rather than requiring navigation. Worth stating as its own mechanism because several open items lean on it:

- Static access-set extraction gets nested-field granularity for free — `Nameplate.title.text` is an offset and a width, not a load-and-chase.
- `where` predicates can address nested fields at the same cost as top-level ones.
- It settles that `value` nesting costs nothing at run time, which is what makes values a free abstraction rather than a structural choice.
- The taint mechanism already carries a field path; flattening turns that path into the offset.

### Memory tiers, handle validity, and null/absence semantics · `pending` · `4`

Carried over from an earlier design layer, not yet reconciled with the current constructs.

The previous iteration's answer to absence is the handle state enum described under [Asynchronous operations](#storage-and-memory-layout) — `Pending` / `Ready` / `Failed` / `Dead`, with `.is_valid()` true only for `Ready`. There is no null and no separate `Result` type; absence, failure and pending completion are the same three-valued question asked of a handle.

Frame-tier memory — bump-allocated, discarded at frame end — is the one tier with worked-out reasoning; it is what would make [GroupBy](Shelved.md#queries-and-predicates) technically safe.

Null coalescing operator (Jose) depends on absence semantics being settled first.

The shape that keeps appearing in practice is a lookup that may fail, immediately bound and used — a conditional binding, where the entity or value is in scope only on the success path. Whatever absence mechanism is chosen has to make that spelling cheap, since it is the common case rather than an edge one.

### Asynchronous operations · `pending` · `4`

Nothing in the current spec addresses operations that do not complete within the frame they were requested — resource and asset loading being the obvious case. Direction from [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#handles--validity): the request returns a handle immediately, and the handle's state enum (`Pending` / `Ready` / `Failed` / `Dead`) is the completion signal. No futures, no callbacks, no suspension — the author polls or matches on state.

No new machinery is required: handle state is an ordinary [enum](Language%20Spec.md#enums), and `match` already binds label payloads, so the polling form falls out of constructs the spec has.

What remains a decision is that handle state carries three jobs at once — absence, fallibility, and async completion. It also means the language has no `Result` type and never needs one, which is a position the current spec has not taken.

Depends on the host embedding API, which is unwritten — see [Runtime & Deployment](Runtime%20&%20Deployment.md#not-yet-written).

### Ownership and `non_serialized` have layout consequences · `pending` · `4`

Both partition storage: a block cannot be blind-copied in a single direction if ownership varies within it, and a non-serialized component cannot share a block with synced data. The engine is expected to organize memory so layout matches these constraints — the same mechanism that will cover streaming/partial loads and interest management.

Open at the language level: how ownership is expressed. Expressing it structurally (a tag or relationship rather than a field) would let archetype partitioning segregate owned from remote entities automatically, and keep it a free presence check in `with`.

Mechanism side is tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

---

## Systems, Scheduling and Parallelism

### Systems as a first-class construct, and dependency declaration · `pending` · `5`

System scheduling and dependency declaration are unspecified. Related and unresolved: whether **systems become a first-class construct**. They were previously judged unnecessary — a query bound to a trigger already covers what a system does — but expressing dependencies may require a named, addressable thing to hang them on, and anonymous self-driving queries give nothing to reference. Raised in conversation with a colleague; not previously written down anywhere.

Note the doc is currently inconsistent on this: [ECS focused](Design%20Principles.md#ecs-focused) lists systems among the primitives the design is organized around, while the language has no system construct at all. Accepted for now. Whichever way this lands, that principle has to be settled with it — reworded if systems become first-class, with the primitive struck from the list if they do not.

Direction settled: a system is an organization and scheduling construct, not a behaviour container. Two pieces of the previous iteration's design ([Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#queries--systems)) are superseded and should not be carried over — `run_query`, made redundant by named queries already being invocable like procedures, and the overridable `tick()` method, replaced by an `on tick` binding. What survives is the shape: a zero-argument block the engine instantiates and script never constructs.

To settle when they are designed: variables stay module-level even if systems become the thing that owns them. A system is not addressable, so reaching a variable as `System.variable` from outside — including from another file in the same module — would make it addressable through the back door. A `public` variable is therefore public to the module and its importers, never a member of a system.

Still to design: how dependencies are declared, whether ordering within a system is positional or explicit, and whether a system is the thing dependencies attach to or merely a namespace.

### Gating machinery on a global condition · `pending` · `4` · `syntax`

A session-wide condition — PvP enabled, a phase change — engages or disengages a whole set of behaviour. Since [listeners are statically bound](Language%20Spec.md#events), the only way to express this today is to write queries that match nothing while the condition is off. That is inadequate on two counts: it forces the global condition to be denormalized into every affected entity, which is the worst available data layout, and the match still costs something per tick.

Three candidate answers, and they overlap, so at most one should be adopted without a case that forces a second.

- *Singleton entity with a loop-invariant term.* Bind a single-cardinality entity and test its field. A term referencing only that binding could be evaluated once and the scan skipped. Rejected as stated, because it relies on unstated optimizer behaviour — the same trap already recorded in [the `with`/`where` boundary](#queries-and-predicates), where recognized and unrecognized predicate shapes are indistinguishable in the syntax.
- *An explicit guard clause,* positioned before `for` and evaluated once. What makes it honest is a restriction rather than a promise: nothing is bound at that position, so the clause may reference no binding and therefore structurally cannot run per entity. Open within it — the keyword, since `when` already introduces `match` arms; whether a guard may call a proc, which requires [purity](#systems-scheduling-and-parallelism) to be settled first; and whether a false guard fires the `else` of [empty-match fallback](#queries-and-predicates), since "never ran" and "matched nothing" are different states.
- *Gating at the system level.* The likeliest fit, because the granularity matches the problem — a mode change engages a set of queries, not one — and a scheduler skipping a system costs a single branch rather than a per-query check. It also needs a named, addressable thing to gate, which is a second and independent argument for systems becoming first-class.

Narrow the problem before choosing. A condition fixed at session start is already fully handled by [load-time conditionals](Language%20Spec.md#load-time-conditionals) at no runtime cost; only conditions that genuinely toggle mid-session justify new machinery, and that set may be small.

### Static access-set extraction · `pending` · `5`

The previous design required explicit per-query read/write declarations, on the grounds that "conflict detection requires declared, not inferred, access sets". The current position is the opposite and is settled: no author-declared access, with the compiler statically extracting per-field read/write sets from imperative bodies.

What remains open is the analysis pass itself — it is what makes parallelism a safe hint rather than an unchecked claim, and it is assumed everywhere and specified nowhere.

Two constraints on where it can sit in the pipeline, both from later decisions:

- A generic proc's access set is per-instantiation, so extraction has to run **after** monomorphization for the scheduler to see the real reads and writes.
- Extraction unions across branches, so a set is an over-approximation — false conflicts, never missed ones. That is what lets [erased component handles](#data-modeling-and-declaration-syntax) stay sound, since every typed access there sits under a narrowing arm.

### Inferred procedure purity · `idea` · `3`

A procedure's purity is derived by the compiler from the same analysis that extracts access sets: a proc that writes no ECS data and calls no impure proc is pure. Nothing is declared, so the common case carries no signature noise, which is the cost Verse pays for its `<computes>`/`<reads>`/`<writes>` effect specifiers and the reason its "learnable as a first language" goal is in tension with its own effect system.

An optional annotation would let an author pin the intent, so a proc meant to stay pure fails compilation when a later edit makes it impure, rather than silently reclassifying.

Two use sites motivate it. First, `where` currently guarantees no mutation only by position: the guarantee holds at the clause boundary and evaporates at a call boundary, since nothing in the spec says whether a proc invoked from `where` may write. Purity is the property that closes it. Second, calling a pure proc as a freestanding statement is dead code, and can be rejected the same way [Statements and Expressions](Language%20Spec.md#statements-and-expressions) already rejects a bare expression that discards its result.

### `parallel` keyword · `idea` · `2` · `syntax`

Highly speculative, and it is not the real design — it sits on top of one that does not exist yet.

The intended model is that the engine builds a DAG from declared dependencies plus whatever parallelization opportunities it can infer, and executes scripts in that order. A `parallel` annotation might end up as one knob the author has over that behaviour, or might not exist at all. Too early to tell.

---

## Data Modeling and Declaration Syntax

### Declaration syntax and semantics · `pending` · `2` · `syntax`

- Reordering so the name doesn't sit between type and annotations (Jose).
- Optional fields and the associated bit-packing idea (Jose).

### Numeric annotations on a composite type · `idea` · `3` · `syntax`

`range` and `precision` annotate a single numeric declaration, so there is no way to constrain a `Vector2`, a matrix, or any other composite of numeric fields. Every author of one currently has to annotate each field by hand and keep them in agreement.

Proposed: an annotation on the type declaration supplies the default for its numeric fields, and a field may override it. The same annotation is also accepted at the use site, constraining that particular value.

```
define value Vector2 precision(2) (
    decimal x
    decimal y                 | both take precision 2
    decimal other precision(5)  | overrides the default
)

Vector2 v precision(3)        | a precision-3 vector
```

The use-site form is the consequential half: `Vector2 precision(2)` and `Vector2 precision(3)` have different layouts, so they are different types. Assignment between them is a rescale, and a proc taking a bare `Vector2` is either restricted to one instantiation or must be generic over the annotation and monomorphized per use. That is the same problem as [an array-typed parameter erasing its element representation](#data-modeling-and-declaration-syntax), with `(range, f)` moving from an array's element to a composite's fields — so it shares that entry's resolution and is blocked on [generics](#data-modeling-and-declaration-syntax).

Open beyond that: whether a use-site annotation may override a field that stated its own, or only fields that took the default; whether `range` composes the same way as `precision`, given a range constrains a single scalar's magnitude and a vector's fields may want different ones; and whether this is the same mechanism as [testing against a declaration's own range](#data-modeling-and-declaration-syntax) asking for annotations to be addressable, or merely adjacent to it.

### Generics and trait/conformance syntax · `pending` · `3` · `syntax`

[Procedure overloading](Language%20Spec.md#procedure-overloading) covers the plain "one name, many types" case, so traits are needed only for generic code.

Sketched in [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#generics--traits), never carried forward. Generics resolve by monomorphization, with `<>` holding any compile-time parameter — type parameters and size parameters alike — and no marker needed, since types are never values and no ambiguity exists to guard against.

Traits declare **fields only**, never procedures. A field is satisfied three ways: a same-named, same-typed field (empty `trait X for Y { }` body); a differently-named field, by alias; or a getter/setter pair. Conformance is always explicit and never structural, including for types the author does not own, primitives included. No access modifiers on trait fields — read/write is the using system's decision, never dictated by the data.

Two things to reconcile when this is taken up:

- Proc-backed trait fields break the assumption that field access is a plain read or write, which [static access-set extraction](#systems-scheduling-and-parallelism) and [flattened component layout](#storage-and-memory-layout) both rely on.
- A hand-written concrete generic query taking precedence over the autogenerated one is a specialization rule, and needs squaring with [procedure overloading](Language%20Spec.md#procedure-overloading).

### Handle lifetime mechanics · `pending` · `4`

Settled: every type is either a value or a handle ([Data Modeling](Language%20Spec.md#data-modeling)). Entities and components are handles with reference semantics, as classes are in a managed language; the difference is that the runtime owns the memory tightly rather than leaving it in a general arena. The earlier proposal that a component's backing be inferred from provenance is superseded — the distinction is carried by the type, so a write's destination is never a fact about where the identifier came from.

This supersedes the previous iteration's sketch in [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#components--lifetime-tiers), where assignment always copied and backing was switched by what the compiler could prove.

Undesigned, and the reason handles can be guaranteed valid:

- A component is created in a temporary memory region and moved into ECS storage at scope exit or at the frame boundary. What the move costs, when exactly it happens, and what happens to a component created and never attached.
- Deletion has to defer to the same boundary, or a handle to a component on an entity deleted mid-frame dangles before it.
- The rule that makes validity structural is that a handle cannot escape its frame: not stored in a component, not in file state, not held across a boundary. That is stated in the spec but the enforcement — and whether it needs an analysis pass or falls out of the type rules — is not designed.
- Deferred structural change is half of [implicit transactional mutation](#errors-and-control-flow) arriving as a consequence rather than as a feature, and it removes the mid-iteration invalidation hazard that entry cites. The two should be settled together.

Blocked on the storage model for the move's cost, not for its semantics.

### Threading construct · `idea` · `2` · `syntax`

A left-to-right spelling for nested calls, so `clamp(get_magnitude(effect), 0, 1)` can be read in application order. Purely syntactic: it would desugar to the same nested calls, with no runtime cost and no effect on overload resolution or access-set extraction.

Prior art splits on where the threaded value lands. Elixir, F# and OCaml insert it as the first argument by convention; Clojure has two operators for first and last; Hack and R use an explicit placeholder token, which states the position at the call site rather than relying on a convention.

Leading candidate is a `then` keyword, threading into the first parameter, with every step written as a call whose first argument is missing:

```
let m = clamp(get_magnitude(effect), 0, 1)             | nested
let m = effect then get_magnitude() then clamp(0, 1)   | threaded
```

The empty parentheses matter: they keep a step a call, so the rule that a bare name in argument position is a reference needs no exception. `|>` was rejected on spelling — `|` is the comment character.

To settle if taken up:

- The call site stops showing real arity. `get_magnitude()` reads as zero-argument but is one; `clamp(0, 1)` reads as two but is three. Resolution in thread position would match arity + 1 with the threaded value first, so a reader must know they are inside a thread to parse a step. Elixir pays the same cost.
- Threading only into the first parameter constrains library design, since a procedure must be written subject-first to be threadable.
- Whether `then` is the right word, given it reads temporal and may be wanted for conditionals.
- Whether the head must be a complete call. `get_magnitude(effect) then clamp(0, 1)` keeps `then` between verbs and leaves the innermost call nested, which is the one place nesting does not hurt. It also means a thread needs at least two operations, since one operation is a plain call.
- Whether a step may have side effects. `then` never writes back, but a mutating step still mutates, and a mixed chain reads as one flowing transformation while half of it is a side effect on ECS data. Restricting steps to side-effect-free procedures makes a thread always a transformation that must be consumed, and leaves mutation in ordinary statements. That depends on [inferred procedure purity](#systems-scheduling-and-parallelism).
- Whether a thread is an expression or a statement form, and how it interacts with the rule that a call without side effects cannot stand as a statement.
- Whether it earns its place at all. It is open to the same objection that shelved [dot-sugar](Shelved.md#data-modeling-and-declaration-syntax): a second way to spell an existing construct. What differs is that it does not imply data owns behaviour. ECS bodies mutate fields more than they transform values, so the pipeline case may be too rare here to pay for a construct.

### `where` clause on procs · `idea` · `3` · `syntax`

A side-effect-free clause at the head of a proc, stating the domain its parameters must satisfy. Semantics are contract failure in every context — never filtering. What varies is the response: a direct call that violates the contract is an error, while an event dispatch that violates it is silently skipped, because skipping is what an event's error response already is. The filter-like behaviour is therefore a consequence of the dispatch context, not a second meaning of the clause.

Motivated as a terser and more declarative alternative to a stack of `assert`/`fail` at the top of a body. Being declarative is the point: a contract in the signature can be displayed by tooling per [Show the machinery in motion](Design%20Principles.md#show-the-machinery-in-motion), where the equivalent imperative guards cannot.

It generalizes machinery the language already has. `integer ammo range(0..999)` is a declarative constraint on a parameter's value; a `where` extends that to constraints a range cannot express. It is also the input-side twin of [an entity type carrying a component invariant](#data-modeling-and-declaration-syntax) — `where e has Flammable` states at the boundary what every caller would otherwise re-check.

The hard question is whether a violation halts or propagates catchably. [Intrinsic fallibility](#errors-and-control-flow) holds the line at derived versus authored: derived failures are catchable, while authored `fail`/`assert` stay terminal so that an invariant violation cannot be swallowed by a caller. A `where` is authored, which by that line makes it terminal — and terminal is not what this idea wants.

The resolution worth testing: a `where` naming a condition that is *already* a derived failure mode — a component that may be absent, a value outside a declared range, a handle that may be dead — is not introducing a failure, it is hoisting an existing one to the boundary. Under that reading it stays catchable without weakening the line, and a `where` over an arbitrary predicate is simply an `assert` and stays terminal. That splits the construct by predicate shape rather than by context, which is checkable.

Open: purity, which waits on [Inferred procedure purity](#systems-scheduling-and-parallelism); whether the clause may read ECS state or only parameters, since the former makes it a per-call runtime cost rather than a static contract; and whether the dispatch case needs [custom event declaration](#events-and-change-detection) settled first, as it presumes parameterized listeners.

Note the breadth pressure. This would be the third `where`-shaped construct alongside the query clause and the proposed [guard clause](#systems-scheduling-and-parallelism). Reusing syntax across contexts is a stated principle, but three contexts with three cost models is how a keyword stops carrying meaning.

### `requires` on components · `mechanism` · `2`

An alternative to inheritance: a component declares a dependency on another. Cascade-removal reuses the existing end-of-frame flush pass, the same mechanism as relationship deletion — reuse, not new machinery. No syntax, no semantics for conflicts or diamond cases.

### Numbers wider than 64 bits · `idea` · `1`

If the 64-bit ceiling ever binds, the answer is a separate type rather than raising the `precision(n)` cap or the storage widths. The ceiling is load-bearing: `f = 17` exists because a product's `fa + fb` intermediate must fit 64 bits, `let` generosity is affordable because 64-bit is the widest thing there is, and [precision selection](Language%20Implementation.md#precision-selection) picks its constant shifts against it. Raising it changes the cost of all arithmetic to buy something almost no code needs, and costs the single-artifact property besides, since wasm3 implements neither i128 nor SIMD.

A separate type also makes the cost visible where it is paid, and can be added later without touching anything that exists — where lifting the cap would change every stored width and every intermediate.

Two things to settle first:

- It is an exception to [Numeric Types](Language%20Spec.md#numeric-types), which states that width and precision come from annotations rather than from separate types. The exception is defensible on the grounds that this is a different operation set — native instructions against synthesized multi-instruction sequences with a per-backend cost — rather than a wider storage width, but it has to be argued rather than assumed.
- "Bigger" is two needs. Enormous magnitude with little precision (idle-game currency, lifetime statistics) wants a floating exponent; more fractional bits than `precision(5)` wants a wider fixed-point type. One type serving both would serve neither well.

### Bit packing · `idea` · `2`

Three directions to explore, not necessarily together:

- Automatic packing of declared booleans within a type.
- A dedicated bitfield primitive.
- Flag enums — power-of-two labels with set operations, against the current rule that a label's value comes from declaration order.

Runs into the alignment rule in [Numeric Representation](Language%20Implementation.md#numeric-representation): numbers are byte-aligned, trading storage efficiency for direct addressability. Packed fields are not directly addressable, so any of these needs a story for how a packed field is read, written and named in an access set. Jose's optional-fields proposal in the declaration syntax pass carries the same idea from a different direction.

A bitfield's membership test is a mask and a compare, so it qualifies for [`in`](Language%20Spec.md#ranges) under the constant-time rule. Odin spells this `x in bits` and is the precedent to follow.

### Sets and maps · `pending` · `2`

The language has arrays and nothing else. Whether a set or a map exists is unspecified, and both run into the same wall as any other container inside a component: the [flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) requires fixed size and no pointers, so a hash-backed container is a `dynamic` field at best, and outside a component at worst.

If they arrive, membership takes [`in`](Language%20Spec.md#ranges) rather than a call, since a hash lookup is constant-time. That is the same rule bit packing qualifies under, and the Odin precedent covers both — `key in m`, `x in bits`.

A map literal is also the other construct that conventionally wants `:`, which is what [the named-argument separator](#data-modeling-and-declaration-syntax) is waiting on.

### Heterogeneous argument packs · `idea` · `3`

[Tuples](Language%20Spec.md#tuples) are capped at four elements and cannot be iterated, so they do not serve the two places the language needs an unnamed heterogeneous sequence: a `create ... with` component list, and a `print`-style argument list. Both are currently grammar — a comma list a construct interprets — and neither can be bound to an identifier.

Varargs does not close this. Varargs is sugar over a stack-allocated array literal, so it is homogeneous by construction; `print("hp: ", hp)` is not.

Two candidate mechanisms, neither designed:

- Variadic generics plus compile-time expansion, which would also remove the asymmetry where `with` can unroll a heterogeneous sequence and no user-written proc can.
- A closed variant. `enum` is already a tagged union with largest-variant layout and is flat-copyable by construction, so an array of a `Printable` enum needs no new type machinery. Costs a conversion at every call site, padding to the largest variant, and closure — another module cannot extend the set.
- A tagged pack: a self-describing byte stream of inline type tag plus payload, walked once, never indexed. Precedent is the ECS command buffer in Unity and Bevy. It is not boxing — the payload is inline and contiguous — but its stride is data-dependent, so it is an encoding for transient and serialized sequences, never a storage layout. The same encoding serves [schema-tagged saved data](#compilation-and-backend) and the deferred command buffer under [handle lifetime mechanics](#data-modeling-and-declaration-syntax).

The fourth option is that `print` is a compiler intrinsic and is simply not expressible in the language. Odin, whose numeric model this language otherwise follows, chose the opposite with `..any`, so this is a real fork rather than an oversight.

Also unspelled: the varargs declaration syntax itself, and where the call-site array's element representation comes from — which is the entry below.

### An array-typed parameter erases its element representation · `discrepancy` · `3`

Storage width is derived from a declaration's `range` and `precision`, and [Numeric Types](Language%20Spec.md#numeric-types) states widths are a guarantee that may be budgeted against. An array declaration carries those annotations once and every element shares them, so an array is homogeneous — but the parameter that receives it is spelled bare.

```
define proc sum(integer[] numbers)
```

`integer x range(0..999)` yields 16-bit elements and a bare `integer` yields 32-bit, and both are `integer[]`. Same for `decimal[]` across differing fractional widths. So that signature either accepts one representation only, or silently rescales — and rescaling an array breaks two stated rules at once: widths as a guarantee, and [parameters are always passed by reference](Language%20Implementation.md#parameter-passing), since a rescale forces a copy of the whole array.

The consistent fix is to make the element representation part of the array's type and generic over it, monomorphized per instantiation — the sized-generic shape sketched in [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#arrays-fixed-strings-symbolstags-sized-generics), extended from capacity to `(range, f)`. That makes this blocked on [generics](#data-modeling-and-declaration-syntax).

Note what does *not* need instantiating: [computation expands every operand to 64 bits](Language%20Implementation.md#arithmetic), so there is no per-width arithmetic to emit — only a widening load, a rescale shift, and a narrowing store. A proc body can compile once and specialize its accessors.

### Erased component handles · `pending` · `3`

A proc taking `Component c` needs no type hierarchy — `Component` is a compile-time constraint and the proc is monomorphized, so `remove_component` works without dispatch. What that does not cover is holding a *set* of differently-typed components: a save file's contents, an editor selection, a batch of removals.

An array cannot hold them, because a single stride cannot cover several layouts. Monomorphization does not help — it duplicates code, and each copy is still homogeneous.

The proposal to design: heterogeneity is permitted only behind indirection, and the language has exactly one indirection — the handle. Component handles are uniform-width and already carry entity plus component identity, so `Component[]` is stride-uniform with no boxing and no largest-variant padding. Frame-locality falls out for free, since a handle may not be stored in a component or held across a frame boundary.

Conditions the design has to keep:

- The constraint bounds the *operations*, not just the type. Type-agnostic structural work only — remove, `has`, whole-copy, serialize — all of which need just entity and component id.
- A typed field is reachable only through narrowing (`if c is Health h`). Exhaustiveness is impossible since the component set is open, so a default arm is mandatory, unlike `enum`'s closed `match`.
- No reflection and no string-keyed access, or [access-set extraction](#systems-scheduling-and-parallelism) becomes incomplete rather than merely imprecise.

Extraction survives under those conditions: a narrowing arm is a branch, and extraction already unions across branches, so the set is an over-approximation — false conflicts, never missed ones. The cost is scheduler precision, and it is opt-in.

Blocked on a `ComponentId` type, which belongs to [the core API](#core-api).

### Bulk entity creation · `idea` · `2` · `syntax`

No syntax for creating many entities at once. A candidate spelling:

```
let batch = create Entity[10] with Health(100), Position
```

The `with` list is evaluated once and shared, so the ten entities are identical. The result is an array of entity handles, which is homogeneous, stack-only and frame-local, so it needs no new rules. What varying per-entity data would look like is undesigned, and it is the reason to keep this open rather than fold it into [Creation](Language%20Spec.md#creation).

### Comparison and equality across data types · `pending` · `3`

[Operators](Language%20Spec.md#operators) lists `== != < <= > >=` without saying which types they apply to. Needs one pass over every type rather than a rule per feature.

Open per type: whether `==` on a `value` or component is structural; whether entity comparison is handle identity, and how a generation counter participates; strings, arrays and tuples; dynamic fields, where a comparison may not be a fixed cost; and whether relational operators exist at all outside numerics.

The enum case is the one already known to be inconsistent, and it is what surfaced the need for the pass. Labels are ordered by declaration order, so `<` and `>` compare labels, while `==` compares values including payload. Two values with the same label and different payloads therefore make `a < b`, `a == b` and `a > b` all false, breaking trichotomy — so sorting or clamping on an enum gets an inconsistent comparator. Three candidate resolutions were raised: state the asymmetry and accept it; make `==` label-only and spell payload comparison separately; or allow relational operators only on payload-free enums, which is checkable at the declaration and covers the real use cases (severity, tiers, weekdays) since those carry no payload.

### Named-argument separator · `idea` · `1` · `syntax`

`:` names a field at construction — `Weapon(damage: 10, ammo: 100)` — and labels an element in a [tuple](Language%20Spec.md#tuples) literal. Worth evaluating whether `=` reads better and is more consistent, since the operation is assigning a value to a named field.

Those two sites are not the same mechanism, despite looking alike. Construction resolves names against a declared field schema and zero-fills what is omitted; a tuple literal has no declaration, so its labels come from the literal itself and no element may be omitted. So `:` already carries two meanings, and a decision here has to move both.

Deferred rather than decided, because the answer depends on whether a dictionary or map literal is ever added. That is the other construct that conventionally wants `:`, and if it arrives, keeping the colon reserved for it may be worth more than the consistency gained here.

### Value constants · `pending` · `2`

Values like `Vector3.left`. Used in [LoomScript Examples](LoomScript%20Examples.md), unspecified in the language.

Ranges are values, so a named range is the same question asked of `range(...)`. Once it is settled, `in` should accept a named range wherever it accepts a literal one.

### Testing against a declaration's own range · `idea` · `2` · `syntax`

`integer ammo range(0..999)` declares a range that has no spelling as an operand, so a test against it has to restate the bounds and can drift from the declaration. A speculative form:

```
if reload_amount in range of ammo
```

Open: whether the range of a declared field is addressable at all, what it means for a field whose range is unbounded on one side, and whether `range of` is worth a two-word operator when the declaration is usually in view.

More generally: whether annotations and constraints are addressable at all.

### Proven presence and flow narrowing · `pending` · `3`

Settled: `is Heal heal` and `has Health health` both test and bind in one construct, and the binding is proven valid by the test. The rule underneath is that component access is infallible exactly where a construct has proven presence — `with` in a query, `has X x` in an expression — and a bare `e.Health` with no such proof stays legal and fallible.

What remains open is whether the compiler should *also* narrow without a binding, so that a bare `e.Health` inside `if e has Health` is known infallible. That is flow-sensitive checking: the fact travels from the condition into the branch, and an intervening call can invalidate it, so it needs purity and access-set information feeding the type checker. Not rejected — the enum case was decided on syntax, not on this cost — but it is a separate decision from the binding form, and it depends on [inferred procedure purity](#systems-scheduling-and-parallelism).

Also unstated: what a component binding refers to after an intervening call removes that component. Under [handle lifetime mechanics](#data-modeling-and-declaration-syntax) structural changes defer to the frame boundary, so the data survives the frame and the write lands on something about to be discarded. Sound, but it needs writing down, since "removed but still writable until the boundary" is not obvious.

### Component single-field coercion · `idea` · `2` · `syntax`

A component whose only field is named `value` could be readable as that field directly — `entity.Position` rather than `entity.Position.value`. Removes the most repeated noise in practice, since single-field wrapper components are the common case. Cost is a second access form for one shape of declaration, and an ambiguity wherever the component itself is the intended operand.

### Entity type carrying a component invariant · `idea` · `2`

A proc returning `Entity` says nothing about what that entity has, so every caller re-checks. A return type of the form "entity known to have these components" would let the check happen once, at the boundary. Interacts with absence semantics, since such a proc usually also has to express "found nothing".

### Where the rounding operations live · `pending` · `2` · `syntax`

[Changing precision](Language%20Spec.md#changing-precision) requires `floor`, `round`, `ceil` and `truncate`, and they are unplaced: language operations, or procedures in [the core API](#core-api). Nothing in the semantics decides it, but the second form has to be expressible by an ordinary signature, and the optional precision argument is the problem — `round(position, precision(2))` passes an annotation as a value.

That is the same question [testing against a declaration's own range](#data-modeling-and-declaration-syntax) asks about `range`, so the two should be answered together. If annotations are never addressable, the precision argument needs a different spelling or the operations are compiler-known.

To review: [Changing precision](Language%20Spec.md#changing-precision) currently spells the argument as a bare `round(position, 2)`, which sidesteps the annotation-as-value problem but makes the second argument a plain number whose unit — decimal places — is implicit. Decide whether that is the intended spelling or a placeholder, since the two forms lead to different answers here.

---

## Queries and Predicates

### The documented `with`/`where` boundary is not the one that costs · `discrepancy` · `4`

[Clauses](Language%20Spec.md#clauses) presents the split in cost terms (fixed presence/bitmap check vs. per-entity runtime evaluation) and then disclaims that it constrains the compiler at all. Both are correct under the intended model: `with` and `where` together form one declarative matching region the compiler may reorder and optimize freely — for instance, servicing a `distance(...)` predicate from a spatial partition rather than per entity. `do` is a freeform imperative block and is largely opaque to that optimization.

The load-bearing boundary is therefore `where` vs. `do`, and the spec does not mention it. An author who hoists a predicate out of `where` into an early exit at the top of `do` — a refactor that looks purely cosmetic — silently forfeits acceleration and converts a partition lookup into a full scan. That is an implicit cost of exactly the kind the design forbids.

A second cost cliff sits inside `where`. If acceleration depends on the compiler recognizing specific predicate shapes, then predicates that match a known form are cheap and equivalent-but-unrecognized ones degrade to per-entity scans, with nothing in the syntax distinguishing them. Either the recognized set is specified, or `where` needs a restricted grammar. The recognized set and its acceleration structures are tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

Spatial partitioning for `distance(...)` is a candidate to evaluate against [No general indexing or materialization](Design%20Principles.md#no-general-indexing-or-materialization), not a violation of it.

### Reductions · `discrepancy` · `4`

Reductions have been pulled from the spec for now, they need further work.

Putting the entire text here for reference: 

> Reductions are special kinds of queries that produce a single value instead of iterating over all results imperatively. A query ending by a reducer instead of a `do` block becomes a value-producing queries usable anywhere a value is expected:
>
> ```
> define query count_dead_units 
> for unit with Unit, without Alive
> count unit
>
> var dead = count_dead_units()
> ```
> 
> `count` and structural/relationship-cardinality reductions cost no additional scan. `sum`/`avg` over a field, and `max_by`/`min_by`, require visiting every matching entity and cost the same as an equivalent hand-written
scan — the language does not disguise this cost as free.
> 
> There is no general materialized or orderable result-set type. Grouping, sorting, and top-N selection are intentionally outside the query language; where needed, they are written as ordinary iteration inside a `proc`.


### Incrementally maintained reductions · `pending` · `2`

Whether `sum`/`count` reductions over a live query can be maintained incrementally (updated on write rather than rescanned on read) — would require exposing the prior value on a `changed` event, which is not yet designed. Mechanism sketched: hook the existing dirty-bitmap/version-per-block change detection and update a running accumulator on write, rather than building new infrastructure.

Deferred rather than solved: access to previous values is a requirement on the ECS design itself, and belongs in the requirement list gathered when that design happens, not here.

### Query amortization and update rates · `pending` · `3`

Budgeted "process N per tick, resume next tick where it left off" work. Reasoning from [Previous Iteration](Previous%20Iteration.md), never carried forward: true coroutines are disallowed, since suspending mid-iteration holds call-stack state across a frame boundary and violates the tier rules. The replacement is a resumable cursor — position and accumulator stored as game-tier state, each resume starting a fresh call-stack scope.

Staggered update rates (e.g. distant entities every other frame) are treated separately and more simply, as bucketing: partition the query by `entity_id % K` and process one bucket per frame, with no suspension mechanism at all.

No syntax for either. Open whether the cursor is author-visible state or a query-level annotation.

### Empty-match fallback, and asymmetry in `for` clauses · `pending` · `4` · `syntax`

A recurring shape has no spelling: run a body per match, and run something else once when an entity matched nothing. Written today it needs a manual flag variable set inside the inner iteration and tested after it, which is noise, and it is easy to get wrong — applying per-non-match what was meant to apply once.

An `else` block on the iteration covers it, with the meaning "the body never ran". Note that Python's `for`/`else` means "no `break` occurred"; the intended meaning here is Jinja's.

The blocker is not the keyword. A [`for` clause](Language%20Spec.md#the-for-clause) today is symmetric — a flat set of bindings the compiler may order freely — so `else` on it can only mean "the whole query produced nothing". Per-entity fallback requires an outer binding and an inner one, which the clause has no way to express. Two candidate shapes:

- *A query nested inside another query's `do` block.* Adds no new clause grammar, and gives a real outer body with statements before and after the inner iteration. But whether a query is a statement at all is unspecified, as is an inner binding referencing an outer one, and `for` would then introduce either a loop or a query depending on `in` versus `with`.
- *Per-level `do`/`else` blocks within one query.* Keeps a single construct, but needs a second optional block per level, and distinguishes nesting from cross-product by punctuation alone — a comma between bindings versus a repeated `for`.

Whichever is chosen, binding order becomes semantically significant and the compiler loses the freedom to reorder the join. That is a cost model change, so it is contract rather than mechanism, and it works against the reordering freedom [The documented `with`/`where` boundary is not the one that costs](#queries-and-predicates) relies on.

---

## Relationships

### Payload storage on symmetric relationships · `pending` · `3`

Storage location for payload data on symmetric or many-to-many relationships, which have no single owning side.

### Quantified negation over a relationship or sub-match · `pending` · `3`

"No entity related to this one satisfies X" — identified as a real gap, no syntax chosen.

### Transitive traversal · `mechanism` · `3`

Needs a real graph walk, and is the one query construct whose cost is genuinely runtime-dependent rather than bounded by the match set. No depth bound decided; see [bounded execution](#errors-and-control-flow). Listed as a TODO in the spec's [Relationships](Language%20Spec.md#relationships) section.

### Ephemeral and exclusive relationships · `pending` · `2`

Listed as a TODO in the spec's [Relationships](Language%20Spec.md#relationships) section, undesigned.

### Direct iteration over a bound relationship's targets · `pending` · `2` · `syntax`

Syntax for iterating a relationship outside a query (e.g. given a held `Entity`, iterating its `Children`) — sketched as reusing the existing `for ... in` loop form, not finalized.

### Wildcard / `any` relationship terms · `mechanism` · `2`

Compile to presence-only bitmap checks with no target materialization — the cheapest possible form, and a distinct codegen path from the named-target case. Named-target terms compile to forward relationship lookups, O(1) per match: a direct index or pointer chase on the source entity's relationship data, not a general join algorithm. Named targets that are never used can be optimized away by static analysis.

---

## Events and Change Detection

### Change-tracking surface · `pending` · `4`

[Change Tracking](Language%20Spec.md#change-tracking) states only that `changed(Component)` fires on the frame a matching component's value changes. Unspecified: granularity (component or field), what counts as a change when a write stores the same value, how it interacts with `with changed` in a `for` clause, and when the flag is cleared relative to system order.

### Custom event declaration · `pending` · `4` · `syntax`

Declaration syntax for custom, game-level events (e.g. `player_joined`) beyond the built-in `tick` / `changed` / `load` triggers. Binding a parameterized event to a query/proc without the trigger's parameter colliding with a `with`-bound name (e.g. `on dead(unit)` alongside a `with`-bound `unit`) is parked pending this.

### `changed(Component)` has no defined meaning on a non-owning peer · `discrepancy` · `4`

Remote state arrives as a raw chunk write rather than a script-initiated mutation. If the engine diffs received chunks and fires `changed`, that is a recurring per-frame cost, against the no-implicit-costs principle. If it does not fire, reactive gameplay code behaves differently on owning and remote peers, which is precisely the networking awareness the design aims to remove. Unresolved; the language cannot stay silent, as `changed` is author-visible.

Mechanism side is tracked in [Language Implementation](Language%20Implementation.md#not-yet-written).

### Deferred execution within a frame · `idea` · `2`

Separated out of the entry above because it is not a listener. The case is "run this once, later" — deferring expensive cleanup past the current point of execution — with nothing captured.

With no capture the cost picture changes completely. Each deferral site is a fixed syntactic location, so what persists is one pending flag per site, sized at compile time. No allocation, no runtime table, and the flag lives in the module that owns it, so a reload takes both together.

Open: whether the resume point is the next tick or a defined point within the current frame; whether two calls before that point coalesce into one run or queue two; whether deferred work is game-tier state that synchronizes, or local by construction and therefore never serialized.

Note the overlap with existing machinery. For an entity, deferral is already expressible as a marker component plus a static query. The capture-free case needs a construct only because there is no entity to hold the marker — the same hole as file-level mutable state in [Declaration syntax pass](#data-modeling-and-declaration-syntax). Settle that first; a singleton store may leave this with no remaining job.

### Periodic scheduling has no construct, and the obvious spelling is wrong · `pending` · `4`

"Do this every N seconds" is ubiquitous in gameplay code and has no support. Written by hand it becomes an accumulator compared against a period, and the natural spelling — a modulo of the accumulated time against the period — is silently wrong: it is true on nearly every tick rather than once per period. Getting it right requires an explicit crossing test against the previous tick's value, which is neither obvious nor discoverable.

This is a pit of failure in the sense [Pit of success](Design%20Principles.md#pit-of-success) rules out: the code reads correctly and behaves wrongly, with no diagnostic.

Two levers, not exclusive. A tick-integer timer in the core API makes the modulo form exact, removing the float error that causes the misbehaviour — see [Engine API](Engine%20API.md#timing). A language-level periodic trigger alongside `tick` would remove the accumulator entirely, but has to answer what happens when a period is shorter than a frame, and whether missed periods coalesce or repeat.

---

## Errors and Control Flow

### Bounded execution · `contradiction` · `3`

Unreconciled, and newly reopened. The previous design flagged loop and recursion limits for determinism as needed but undesigned, noting there is no GC pause to blame instead. Transitive relationship traversal is the first construct with genuinely runtime-dependent cost and has no max-depth safeguard, which makes the gap concrete rather than theoretical.

[Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#error-handling) does answer it, and cheaply: a simple runtime execution cap that halts on exceeding it, with no proof-of-termination requirement and no annotations. Worth adopting or rejecting explicitly rather than leaving the gap open.

### Halt unwind granularity · `pending` · `3`

[Error Handling](Language%20Spec.md#error-handling) says `fail` halts script execution, but not how far the halt travels. The previous iteration specified it precisely: a halt unwinds to the nearest engine-called entry point. A tick function aborts the whole tick; a query callback aborts only that entity's iteration and the rest continue; a cursor resume aborts only that resume.

That granularity is what makes [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient) concrete. It also draws a line the current spec does not: expected absence (a dead handle, an unloaded resource, a missing optional component) is never a halt, and is handled through handle state instead.

The previous iteration kept the boundary unambiguous by forbidding a query from invoking another query. The current spec has named queries "manually invoked" ([Queries](Language%20Spec.md#queries)) and places no restriction on where from, so the question the ban avoided is live here. A halt inside a nested query has no defined stopping point: the inner query's current entity, the outer one's, or the whole trigger.

Naming: the previous iteration used `halt` rather than `fail`, on the grounds that it communicates only the current entry point stopping. The current spec uses `fail`.

### Error propagation and catching · `idea` · `2`

The spec has `fail` and `assert` ([Error Handling](Language%20Spec.md#error-handling)); propagation and recovery are unspecified. Proposed (Jose): proc calls automatically propagate failures upwards, with some keyword to catch them. Must be weighed against [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient).

### Intrinsic fallibility · `idea` · `4`

An alternative to the entry above, and a generalization of it. Failure becomes a property of an expression rather than a construct layered on top of calls. An operation the compiler knows can fail — component access on an entity that may not have it, index out of bounds, division or modulo by zero, a dead handle, a relationship with no target, a value outside a declared range, a narrowing coercion — is *fallible*, and a fallible expression only type-checks inside a context that handles failure. `if` is that context; there is no catch keyword and no new syntax. The feature is subtraction.

Fallibility is inferred, by the same pass as [Inferred procedure purity](#systems-scheduling-and-parallelism). A proc containing an unguarded fallible expression is itself fallible, so calling it is itself a fallible expression. That gives Jose's upward propagation, but typed: propagation is real, and every frame in the chain opted in visibly at compile time rather than by an invisible unwinding path.

The line to hold is derived versus authored. Everything above is derived — the compiler knows the operation has a failure mode. `fail` and `assert` are authored, stay terminal, and are not catchable; if an invariant violation becomes recoverable, any caller can swallow it. This also settles the distinction [Halt unwind granularity](#errors-and-control-flow) needs, where expected absence is never a halt.

Declared ranges are what makes this affordable here and not in Verse. Verse forces a guard on every division because it knows nothing about the divisor; ranges are already stated in this language, so `a / b` is infallible when `b`'s range excludes zero, and arithmetic is infallible when the result's range fits the target. Overflow stops being a separate concept — it is a result that does not fit the target's range. The ergonomic consequence inverts in the language's favour: a required guard is a signal that the author under-specified the domain, so the remedy is to state the range, which is [Domain over technicism](Design%20Principles.md#domain-over-technicism) exactly.

It also collapses `has`. A fallible expression in `where` means the entity is filtered out, so structural presence and value predicates become one rule and `with` is its accelerable form. Open: filtered-because-absent and filtered-because-false become indistinguishable, which is a silent-skip path to accept or reject deliberately.

Costs. Range arithmetic becomes load-bearing type checking rather than metadata — interval propagation through the arithmetic operators, decidable at the load boundary, and specified, since an equivalent-but-unrecognized range expression degrading to fallible is the same cost cliff as the `where` predicate-shape problem above. An infallible escape is needed where refinement cannot prove safety — saturating or wrapping operators, explicit at the call site, with fallible as the default. Viability is entirely a function of how strong the range analysis is: with weak refinement, guards proliferate and [Readable by non-engineers](Design%20Principles.md#readable-by-non-engineers) is lost, so this is not adoptable independently of that analysis. Runtime cost is a branch the author wrote, with no unwinding machinery, which suits the AOT and interpreter targets. Still to decide: that nothing binds on failure, including multi-return tuples; and the interaction with **Implicit transactional mutation** below, since a fallible proc that wrote before failing leaves partial mutation unless the write buffer is scoped to the fallible call.

### Implicit transactional mutation · `idea` · `3`

Raised as a counterpart to Verse's `<transacts>` rollback, but arrived at from the opposite direction: Verse needs an author-declared effect and a general transactional memory, whereas the compiler here already sees every write to ECS data (see [Static access-set extraction](#systems-scheduling-and-parallelism)). If every mutation in a scope is known statically, the scope's writes can be buffered and applied atomically on successful exit, with structural changes deferred to a frame boundary.

Two properties would follow. A halt would leave no partially mutated world, which is what makes [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient) a real guarantee rather than a best effort, and it directly affects what **Halt unwind granularity** above has to specify. Deferred structural change also removes the mid-iteration invalidation hazard that handle stability currently has to absorb.

Open, and not obviously affordable. Buffering writes is a copy and a commit pass that the author did not ask for, which is exactly the shape [No hidden control flow, no implicit costs](Design%20Principles.md#no-hidden-control-flow-no-implicit-costs) forbids, so the analysis has to establish that the buffer is bounded and statically sized before this can be considered. Also unresolved: whether the transactional scope is the query body, one entity's iteration, or the trigger; and whether reads within a scope observe its own uncommitted writes.

### Scope-escaping keywords · `pending` · `3` · `syntax`

The language has `return` and nothing else. Loops have no way to stop early or skip an iteration, a query body cannot advance to the next match, and a `match` arm cannot state that it deliberately does nothing.

Needs one pass over every escaping form rather than a keyword per context. The candidates, and the scopes they would apply to:

- Leaving a loop entirely (`break`).
- Advancing to the next iteration (`continue`, `skip`).
- Advancing to the next query match, which is the same idea against a different scope.
- An explicit no-op (`pass`), which escapes nothing and exists only so a reader can tell a deliberately empty branch from an unfinished one.

Writing against the current spec surfaced that the last two are distinct needs a single keyword should not serve. Advancing to the next match is the early exit proper; the no-op is a readability construct with no control-flow effect, most often wanted on a `match` arm, and could be spelled separately.

Open: whether one keyword can serve loops and query bodies, given that their costs differ; whether the no-op is worth a keyword at all when a comment already conveys it; and whether any form may cross a query body's boundary, since [empty-match fallback](#queries-and-predicates) and the `where`/`do` split both depend on what the body may do. An early exit inside `do` is also the refactor that silently forfeits acceleration, so it interacts directly with [the `with`/`where` boundary](#queries-and-predicates).

When this settles, update the [Enums](Language%20Spec.md#enums) example, whose `when Nothing` arm is currently annotated with a `| no-op` comment where a keyword would be clearer.

### Alternative ternary syntax · `idea` · `1` · `syntax`

With the condition first (Jose).

---

## Compilation and Backend

### Width-specialized computation · `idea` · `2`

[Arithmetic](Language%20Implementation.md#arithmetic) expands operands to 64 bits. Generating variants of math primitives and procs against the widths actually used would cut that, but it is exclusively a performance improvement — the naive path must be correct on its own.

### Host embedding API · `pending` · `5`

What the engine exposes to guest modules and how capabilities are granted is unwritten. Blocks [asynchronous operations](#storage-and-memory-layout) and the whole I/O surface below.

### Reload semantics for live state · `pending` · `4`

[Hot reload](Runtime%20&%20Deployment.md#hot-reload) swaps a module's Wasm object, but what happens to entities and component data whose defining module is being swapped is undefined.

File-level variables are [Unmanaged](Engine%20Core.md#memory-tiers) and so are discarded by the swap, coming back zero-initialized. Whether that self-heals depends on an unsettled question: does `load` re-fire on reload? Least surprise says yes, and a table populated in `on load` needs it to, or it stays zero forever. But on the second firing the world already holds the entities the first firing created, so re-firing duplicates them unless this entry says what happens to them. The two halves have to be answered together.

### Observable agreement between backends · `pending` · `3`

Whether AOT and interpreted backends must agree observably — execution bounds, numeric edge cases — or may differ. Fixed-point arithmetic removes most of the float divergence risk, but bounded execution (see [Errors and Control Flow](#errors-and-control-flow)) is decided per backend unless this is pinned.

### I/O surface · `pending` · `3`

Input, audio, asset loading, save files, network transport. Not excluded by the design, simply unspecified as host-exposed capabilities. Blocked on the host embedding API.

### Schema-tagged saved data · `pending` · `3`

Synchronization assumes every peer pre-agrees on all data schemas — component ids, layouts, enum ordinals — so nothing on the wire needs an identifier that is stable independently of the build. Saved data is the case where that assumption does not hold, since it outlives the build that wrote it.

Direction settled: the schema travels with the data. A save stores the schema it was written against, and load remaps into the current schema when the two differ. Version skew is therefore handled once, in the save path, rather than by freezing identifiers across the language.

Undesigned: what a stored schema contains, which changes are remappable and which are a hard failure, whether remapping is automatic or author-directed, and whether the same mechanism covers a module swapped by hot reload. Blocked on the storage model, since what a schema has to describe depends on it.

### Load-time branch elimination is an optimization, not a guarantee · `discrepancy` · `2`

Deliberate — evaluating the condition at run time is equally correct, so promising elimination would over-constrain the backend. But it leaves an author with no language-level assurance that a branch behind an absent module costs nothing, which is the shape of implicit cost [No hidden control flow, no implicit costs](Design%20Principles.md#no-hidden-control-flow-no-implicit-costs) rules out.

Resolution direction: tooling rather than spec — surface what was stripped and what survived, per [Show the machinery in motion](Design%20Principles.md#show-the-machinery-in-motion). A guarantee stated in the language would buy the same confidence at the cost of pinning the backend.

### Const-eval of pure procedures · `idea` · `2`

[Constants](Language%20Spec.md#constants) binds a name to an expression built from literals and other constants, so any value that needs computation cannot be a constant and has to be hand-computed into a magic number. Verse's "just one language" principle is the opposite position — the same constructs run at compile time and run time — and the cheap version of it applies here: once purity is inferred ([Inferred procedure purity](#systems-scheduling-and-parallelism)), a pure proc called with constant arguments is itself a constant, and the load-time evaluator needed for load-time conditionals already exists. Derived constants — lookup tables, precomputed curves, a size from a formula — become expressible without a separate mechanism.

Same inference-plus-optional-annotation shape as purity. Const-eval is implicit wherever the arguments are constant, so the common case carries no ceremony; an optional annotation pins the intent, so a binding meant to be resolved at load time fails compilation if a later edit makes it runtime-dependent rather than silently becoming a per-execution computation.

Open: interaction with the existing rule that constants depending on a load-time conditional cannot determine data layout, since a const-eval'd proc widens what can reach an array bound or range annotation; and termination, since a const-eval'd call must complete at the load boundary, which ties it to **Bounded execution** above.

### Bundled source produces private types · `pending`

From the previous iteration: sharing source between modules by local bundling, without registering a module, yields a distinct private type per bundler — by design, not as a defect. Sharing a real type requires a proper module dependency. Unstated in [Program Structure](Language%20Spec.md#program-structure), and the kind of rule that is discovered the hard way if left implicit.

---

## Core API

### The core API surface is unspecified · `pending` · `4`

Scripts already depend on a body of engine-provided types and procedures that no document describes — vector types and their value constants, random number generation, elapsed tick time, geometric predicates, and ordinary math. [Engine API](Engine%20API.md) now holds the boundary and the areas; almost none of the contents are settled.

Distinct from the [host embedding API](#compilation-and-backend), which is about what capabilities the host grants a guest module. The core API is present in every deployment and is not a capability question.

One member is already load-bearing elsewhere: a `ComponentId`, a runtime value naming a component type. [Erased component handles](#data-modeling-and-declaration-syntax) needs it, structural changes driven by data — save files, network messages, editor selections — need it, and it is what lets a deferred removal be recorded without holding the component. It is an identifier, not polymorphism.

### Timer primitive · `mechanism` · `3`

Proposed representation, carried over from prior work in another engine: a starting tick number plus a duration in ticks. Fixed size, no indirection, so it passes [the flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) with no taint and can sit in a component directly.

The property that earns it is that it is read-only until it fires. A countdown timer writes on every tick on every entity holding one, producing sync traffic and change-detection churn on data nobody asked about; a start-plus-duration timer is compared, not mutated.

Integer ticks also remove the float error behind [periodic scheduling](#events-and-change-detection) being wrong when written naively.

One hazard to resolve before adopting it. An absolute start tick is only meaningful against an agreed tick origin. Copied to a peer whose counter differs, it silently yields the wrong deadline — and [Transparent networking](Design%20Principles.md#transparent-networking-and-serialization) promises the author never has to think about that. A countdown survives resync; start-plus-duration does not. The same question applies to a module swapped by hot reload.

Open regardless of representation: whether the authored surface is in seconds and converted at load per [Resolve at compile/load time](Design%20Principles.md#resolve-at-compileload-time), which [Domain over technicism](Design%20Principles.md#domain-over-technicism) argues for, and whether one-shot and repeating are one construct or two.

---

## Spec Consistency

### `LoomScript Examples.md` and the spec disagree · `contradiction` · `2`

Examples now follow the spec. Most of the earlier list turned out to be spec lag rather than aspirational syntax: parentheses are optional wherever a construct reads unambiguously without them, so the examples were already idiomatic and the spec was missing the rule. Component access casing was the one real fix.

Still divergent, because the spec has no position to sync to:

- `Vector3.left` — see [value constants](#data-modeling-and-declaration-syntax).

### Range violation: which build halts where · `pending` · `3`

Settled and written into [Ranges](Language%20Spec.md#ranges): never wrap, halt on out-of-range writes, clamp only via explicit syntax. What is not settled is which range is enforced in which build:

- *Debug halts over the exact declared range, release over the representable range.* Conventional, cheap in release, but the two builds are then different programs. A value outside `range(0..100)` but inside a signed byte survives in release and halts in debug.
- *Warn over the exact range, halt over the representable range, in all modes.* Build-independent.

The second is worth the weight it costs, because of networking. State is bulk-synchronized between peers, so a peer on a debug build and a peer on a release build diverging on the same input is a desync, not just a debugging inconvenience. Build-dependent halt behaviour makes the declared range an invariant in one build and a hint in the other.
