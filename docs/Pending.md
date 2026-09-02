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

Undecided, needs its own design pass. Constraints in [Engine Core](Engine%20Core.md#constraints). Two candidates:

- *Archetype/table.* Grouped by component set, contiguous. Structural changes move the entity and invalidate handles; deferring removal does not fix it, since adds relocate too. Fails handle stability as stated.
- *Inverted hierarchical bitmap.* A bitmap per component over entity slots; entities never move, so handle stability holds structurally. Empty blocks don't materialize, so memory cost tracks entity-ID clustering, not architecture.

Root blocker for the rest of this section, for `changed` on a non-owning peer, and for handle validity — whether an unrelated entity's mutation can invalidate a handle is a property of the model, not the handle. The ownership entry below presumes archetype partitioning it has not earned.

Held here, not examinable before the model is chosen:

- *Copy granularity.* Unit of transfer between peers: memory block, sub-range, or single component.
- *Storage for pointer-like component data.* The ECS-managed buffers an `external` field selects. Their semantics are settled — see [Collections](Language%20Spec.md#collections) and [Storage](Language%20Spec.md#storage) — but their layout is not.

### Entity identity and generation · `pending` · `4`

Unspecified: ID composition, whether there is a generation counter, what a stale ID resolves to. Blocked on the storage model.

Encoding must be canonical — no spare bits, no two patterns naming one entity — since [handles compare whole](Language%20Spec.md#comparison-semantics).

### The synchronization path · `pending` · `3`

Memory block selection, delta compression, peer topology — all unwritten. [Frame Model](Engine%20Core.md#frame-model-and-synchronization) records only the premise: per-frame chunk copies, a peer either owning or receiving. `non_serialized`, bit packing and the flat-copyable rule are all written against it.

### Layout of nested external data · `pending` · `4`

[External data may appear at any depth](Language%20Spec.md#storage). That is settled contract; how it is laid out is not.

Settled, and why the promise is safe to make: [an author cannot install a handle into stored data](Language%20Spec.md#data-modeling), so every nested reference is runtime-made and the discriminant distinguishing ECS-managed from general memory is static — decided by where the field lives, never at run time. A per-pointer check at sync time, and silent corruption in networked builds, are both off the table. The earlier requirement that promotion be an explicit named operation is discharged too: [field assignment stores contents](Language%20Spec.md#data-modeling), so writing a record with nested external fields into a component is already a deep copy by a rule the spec states.

Open:

- One pointer representation, or two? A block-relative offset survives blind copying and a general pointer does not, so a `value` on the stack and the same `value` in storage may need different layouts at the same size.
- What a copy into storage costs. Deep copy plus reference fixup, proportional to nested content; the references themselves come from walking the [flattened layout](Engine%20Core.md#component-flattening).
- "Block-relative" presumes archetype storage; under inverted bitmaps there may be no block to be relative to. Blocked on the [storage model](#storage-and-memory-layout).

Stated objective (Joaquin, 2026-09-01): make [the synchronization path](#storage-and-memory-layout) treat an `external` field as cheaply as an inline one, at which point the [placement annotation](Language%20Spec.md#storage) has no consequence left to announce and can be dropped. Reads and copies can plausibly reach chunk-cost; growth cannot, since a length change is a structural change, so the surviving distinction may be fixed-size against resizable rather than inline against external.

### Flattened component layout · `mechanism` · `3`

Fixed component layout, so nested `record` fields are static offsets, not navigation. Stated separately because several items lean on it:

- Access-set extraction gets nested-field granularity free — `Nameplate.title.text` is offset plus width, not load-and-chase.
- `where` predicates address nested fields at top-level cost.
- `record` nesting costs nothing at run time, which makes records a free abstraction rather than a structural choice.
- The taint mechanism already carries a field path; flattening turns it into the offset.

### Memory tiers, handle validity, and null/absence semantics · `pending` · `4`

Carried from an earlier design layer, not reconciled with current constructs.

Previous iteration's answer to absence: the handle state enum (`Pending` / `Ready` / `Failed` / `Dead`, valid only when `Ready`). No null, no `Result` — absence, failure and pending completion are one three-valued question.

Frame-tier memory (bump-allocated, discarded at frame end) is the one tier with worked-out reasoning, and is what would make [GroupBy](Shelved.md#queries-and-predicates) safe.

The recurring shape is a lookup that may fail, immediately bound and used — a conditional binding, in scope only on the success path. Whatever is chosen must make that cheap; it is the common case. Null coalescing (Jose) waits on this.

### Asynchronous operations · `pending` · `4`

Nothing addresses operations outstanding past their frame — asset loading being the obvious case. Direction ([Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#handles--validity)): the request returns a handle immediately and its state enum is the completion signal. No futures, callbacks or suspension; the author polls or matches.

Needs no new machinery — handle state is an ordinary [enum](Language%20Spec.md#enums) and `match` already binds payloads.

To decide: that handle state carries absence, fallibility and async completion at once, and that the language therefore has no `Result` type and never needs one. The spec has not taken that position.

Depends on the host embedding API, unwritten.

### Ownership and `non_serialized` have layout consequences · `pending` · `4`

Both partition storage: a block cannot be blind-copied one direction if ownership varies within it, and non-serialized data cannot share a block with synced data. Same mechanism expected to cover streaming, partial loads and interest management.

Open: how ownership is expressed. Structurally (tag or relationship, not a field) would let partitioning segregate owned from remote automatically and keep it a free presence check in `with`.

---

## Systems, Scheduling and Parallelism

### Systems as a first-class construct, and dependency declaration · `pending` · `5`

Scheduling and dependency declaration unspecified. Previously judged unnecessary — a query bound to a trigger covers what a system does — but declaring dependencies may need a named, addressable thing to hang them on, and anonymous self-driving queries give nothing to reference.

Settled: a system is an organization and scheduling construct, not a behaviour container — a zero-argument block the engine instantiates and script never constructs. `run_query` and the overridable `tick()` ([Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#queries--systems)) are superseded by invocable named queries and `on tick`. Variables stay module-level even if systems own them: a system is not addressable, and `System.variable` would make it so through the back door.

Open:

- How are dependencies declared?
- Is ordering positional or explicit?
- Do dependencies attach to a system, or is it just a namespace?
- Define or annotation? Same question as [query as a form inside a proc](#queries-and-predicates), cheaper to decide there first.

[ECS focused](Design%20Principles.md#ecs-focused) lists systems as a primitive while the language has none. Settle with this.

### Gating machinery on a global condition · `pending` · `4` · `syntax`

A session-wide condition (PvP enabled, a phase change) engages or disengages a set of behaviour. [Listeners are statically bound](Language%20Spec.md#events), so the only expression today is a query matching nothing while off — denormalizing the condition into every affected entity, and still costing a match per tick.

Narrow first: conditions fixed at session start are already free via [load-time conditionals](Language%20Spec.md#load-time-conditionals). Only mid-session toggles justify machinery, and that set may be small.

Three overlapping candidates; adopt at most one without a case forcing a second.

- *Singleton entity with a loop-invariant term.* Rejected — relies on unstated optimizer behaviour.
- *Explicit guard clause* before `for`, evaluated once. Honest by restriction, not promise: nothing is bound there, so it structurally cannot run per entity. Open — which keyword, since `match` has `when`? May it call a proc (needs [purity](#systems-scheduling-and-parallelism))? Does a false guard fire the `else` of [empty-match fallback](#queries-and-predicates), given "never ran" and "matched nothing" differ?
- *System-level gating.* Likeliest fit — granularity matches the problem, and skipping a system is one branch rather than a per-query check. Needs a named thing to gate: a second, independent argument for first-class [systems](#systems-scheduling-and-parallelism).

### Static access-set extraction · `pending` · `5`

Settled: no author-declared access sets; the compiler extracts per-field read/write sets from imperative bodies. Reverses the previous design, which required declarations on the grounds that conflict detection needs them.

The analysis pass itself is unwritten, and everything about scheduling assumes it. Two constraints on where it sits in the pipeline:

- Must run **after** monomorphization — a generic proc's access set is per-instantiation.
- Unions across branches, so sets over-approximate: false conflicts, never missed ones. That is what keeps [erased component handles](#data-modeling-and-declaration-syntax) sound, since every typed access sits under a narrowing arm.

### Inferred procedure purity · `idea` · `3`

Purity derived by the compiler, reusing access-set extraction: writes no ECS data and calls no impure proc. Nothing declared, so the common case carries no signature noise. An optional annotation pins intent, so a proc meant to stay pure fails compilation when a later edit makes it impure.

Two use sites motivate it:

- `where` currently guarantees no mutation only by position — the guarantee evaporates at a call boundary, since nothing says whether a proc invoked from `where` may write.
- A pure proc called as a freestanding statement is dead code, rejectable the same way [Statements and Expressions](Language%20Spec.md#statements-and-expressions) rejects a discarded result.

---

## Data Modeling and Declaration Syntax

### Declaration syntax and semantics · `pending` · `2` · `syntax`

- Reordering so the name doesn't sit between type and annotations (Jose).
- Optional fields and the associated bit-packing idea (Jose).

### Numeric annotations on a composite type · `idea` · `3` · `syntax`

`range` and `precision` annotate one numeric declaration, so a `Vector2` or matrix cannot be constrained as a whole — every author annotates each field by hand and keeps them in agreement.

Proposed: an annotation on the type defaults its numeric fields, a field may override, and the same annotation is accepted at the use site.

```
define record Vector2 precision(2) (
    decimal x
    decimal y                   | both take precision 2
    decimal other precision(5)  | overrides the default
)

Vector2 v precision(3)          | a precision-3 vector
```

The use-site form is the consequential half: different annotations mean different layouts, so different types. Assignment is a rescale, and a proc taking a bare `Vector2` is either pinned to one instantiation or generic over the annotation. Same problem as [an array-typed parameter erasing its element representation](#data-modeling-and-declaration-syntax) — shares that resolution, blocked on [generics](#data-modeling-and-declaration-syntax).

Open:

- May a use-site annotation override a field that stated its own, or only defaulted fields?
- Does `range` compose like `precision`, given a vector's fields may want different magnitudes?
- Same mechanism as [are annotations addressable](#data-modeling-and-declaration-syntax), or merely adjacent?

### Generics and trait/conformance syntax · `pending` · `3` · `syntax`

[Overloading](Language%20Spec.md#procedure-overloading) covers "one name, many types", so traits are needed only for generic code.

Sketched in [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#generics--traits), never carried forward. Monomorphized, `<>` holding any compile-time parameter — type or size — no marker needed, since types are never values.

Traits declare **fields only**, satisfied three ways: same-named same-typed field, a differently-named field by alias, or a getter/setter pair. Conformance always explicit, never structural, including foreign types and primitives. No access modifiers — read/write is the using system's decision.

**Conformance by proc shape.** Alternative for capability annotations: the compiler finds a procedure of the right shape instead of a declared conformance — `ordered` would require `Compare(T a, T b) returns integer`. Reuses [signature](Language%20Spec.md#signatures), so no conformance sublanguage. Three-way rather than a `<` predicate, so a sort makes one call per comparison; `ItemComparison` returns `boolean` and wants reconciling. Also how `ordered` extends past enums to records and tuples, otherwise unspellable. No use case yet.

- Is a capability request different enough from a trait to follow a different rule? It cuts against fields-only and explicit-never-structural.
- Proc-backed fields break field-access-is-a-read, which [access-set extraction](#systems-scheduling-and-parallelism) and [flattened layout](#storage-and-memory-layout) rely on. Same hazard for conformance by shape on a hot path.
- Hand-written concrete generic queries beating autogenerated ones: a specialization rule, to square with [overloading](Language%20Spec.md#procedure-overloading).

### Handle lifetimes and lifetime mechanics · `pending` · `4`

Two halves of one question, each previously blocked on the other: which lifetime regime a handle kind follows, and the machinery that makes the frame-scoped regime hold.

Lifetime is a property of the handle's kind, not of handle-ness. The spec stated the entity-and-component rule as though it covered all handles; that paragraph was removed rather than corrected, so the spec now says nothing about any handle's lifetime. Belongs in a lifetime and memory section that does not exist.

- *Frame-scoped, structurally valid.* Entities and components. Escaping the frame is unspellable, so validity needs no runtime check and deferred deletion is safe.
- *Long-lived, checked.* Resource handles are stored and held across frames, so validity is a runtime question. Sketched answer is the handle state under [memory tiers](#storage-and-memory-layout). Unwritable until resources exist as a language concept.

Open:

- Is lifetime declared per handle type, or does it follow from what it points at?
- How is a long-lived handle's validity spelled at the use site?
- What does [identity equality](Language%20Spec.md#comparison-semantics) mean for a dead handle?

**Mechanics**, undesigned, and why frame-scoped handles can be guaranteed valid:

- Components move from a temporary region into ECS storage at scope exit or frame boundary. Cost? Exact timing? What happens to one created and never attached?
- Deletion must defer to the same boundary, or handles dangle mid-frame.
- The escape rule — never stored, never held across a boundary — is what makes validity structural. Unstated in the spec; enforcement undesigned.
- Deferred structural change is half of [implicit transactional mutation](#errors-and-control-flow), and removes the mid-iteration invalidation hazard. Settle together.

Blocked on the storage model for the move's cost, not its semantics.

### `where` clause on procs · `idea` · `3` · `syntax`

A side-effect-free clause at the head of a proc, stating the domain its parameters must satisfy. Contract failure in every context, never filtering — a violating call is an error, a violating event dispatch is skipped, because skipping is already an event's error response. Filter-like behaviour comes from the dispatch context, not a second meaning.

Declarative, so tooling can display the contract where a stack of `assert`/`fail` cannot. Extends what `range(0..999)` does to constraints a range cannot express. Input-side twin of [an entity type carrying a component invariant](#data-modeling-and-declaration-syntax).

Does a violation halt, or propagate catchably? [Intrinsic fallibility](#errors-and-control-flow) makes authored failures terminal, and a `where` is authored — not what this wants.

Worth testing: a `where` naming an *already*-derived failure mode (absent component, out-of-range value, dead handle) hoists an existing failure rather than introducing one, so it stays catchable; over an arbitrary predicate it is an `assert`, terminal. Splits by predicate shape, not context, which is checkable.

Open:

- Purity, waiting on [inferred purity](#systems-scheduling-and-parallelism).
- May it read ECS state, or only parameters? The former makes it a per-call cost, not a static contract.
- Does the dispatch case need [custom events](#events-and-change-detection) first? It presumes parameterized listeners.

Breadth pressure: third `where`-shaped construct, alongside the query clause and the proposed [guard clause](#systems-scheduling-and-parallelism). Three contexts with three cost models is how a keyword stops carrying meaning.

### Commands, and the paren-less call rule · `idea` · `2` · `syntax`

A declared command form, replacing the general rule that [a call may drop parens as a zero-or-one-argument statement](Language%20Spec.md#procedures). Paren-less calling becomes opt-in at the definition site.

Two motivations, worth keeping only because they meet:

- *Syntax.* The current rule has three memorized exceptions — reference-or-call by position, argument running to end of statement, no nesting — collapsed into one by an opt-in form.
- *Console.* A Source-style console needs a compiler-visible command table for dispatch, help and completion, and [no reflection](Language%20Spec.md#non-goals) closes the attribute-plus-runtime-scan route.

Gating (`cheat`, `dev`), console variables and shipping-build stripping fall out of existing machinery: [annotations](Language%20Spec.md#annotations), an annotated top-level variable whose `range` gives validation bounds, and [load-time conditionals](Language%20Spec.md#load-time-conditionals).

N arguments do not reopen the ambiguity. *Position* is what makes a bare call safe — statement position only, never nested — so a bare name in argument position is always a reference. The one-argument limit solved a different problem, where an argument ends, which commas solve at any arity. One declaration, two call grammars: commas in script, whitespace tokens at the console.

Open:

- Define or annotation? The annotation is cheaper and decouples the motivations; define is better for the failure boundary.
- How is failure handled? Commands have a fallible entry path (console) that procs don't. See [intrinsic fallibility](#errors-and-control-flow).
- Is overloading allowed? Probably not; ambiguous for the console.
- Can a command be referenced? eg `bind "e", noclip`. Reuse signatures?
- Parsing limits allowed params? Primitives fine, entity ids tempting, composites not.
- Scoped names? `combat.give` reads badly at a prompt.
- Where is help text defined?
- Does a bare zero-argument proc statement stay legal?

### `requires` on components · `mechanism` · `2`

A component declares a dependency on another, as an alternative to inheritance. Cascade-removal reuses the end-of-frame flush pass, same as relationship deletion. No syntax, no semantics for conflicts or diamonds.

### Bit packing · `idea` · `2`

Three directions, not necessarily together: automatic packing of declared booleans; a dedicated bitfield primitive; flag enums with power-of-two labels and set operations, against the rule that a label's value comes from declaration order.

All run into byte alignment ([Numeric Representation](Language%20Implementation.md#numeric-representation)) — packed fields are not directly addressable, so each needs a story for how one is read, written and named in an access set. Jose's optional-fields proposal is the same idea from another direction.

A bitfield is collection-like, so membership takes [`in`](Language%20Spec.md#membership-semantics) — a mask and a compare. Odin's `x in bits` is the precedent.

### Sets and maps · `pending` · `2`

Unspecified whether either exists. Both hit the same wall as any container inside a component: the [flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) wants fixed size and no pointers, so a hash-backed container is an `external` field at best and outside a component at worst.

If they arrive, membership takes [`in`](Language%20Spec.md#membership-semantics), as for every other collection — `key in m`, and Odin covers bit packing the same way.

A map literal is the other construct that wants `:`, which [the named-argument separator](#data-modeling-and-declaration-syntax) is waiting on.

### Heterogeneous argument packs · `idea` · `3`

[Tuples](Language%20Spec.md#tuples) cap at four and cannot be iterated, so they do not serve the two places needing an unnamed heterogeneous sequence: a `create ... with` list, and a `print`-style argument list. Both are grammar today — a comma list a construct interprets — and neither can be bound.

Varargs does not close it: sugar over a stack array literal, homogeneous by construction, and `print("hp: ", hp)` is not.

Four candidates, none designed:

- *Variadic generics* plus compile-time expansion. Also removes the asymmetry where `with` unrolls a heterogeneous sequence and no user proc can.
- *A closed variant.* `enum` is already a flat-copyable tagged union, so an array of a `Printable` enum needs no new machinery. Costs a conversion per call site, largest-variant padding, and closure — another module cannot extend the set.
- *A tagged pack:* inline tag plus payload, walked once, never indexed (precedent: Unity and Bevy command buffers). Not boxing, but data-dependent stride, so it encodes transient and serialized sequences, never storage. Same encoding serves [schema-tagged saved data](#compilation-and-backend) and the deferred command buffer.
- *`print` is a compiler intrinsic* and not expressible. Odin chose the opposite with `..any`, so this is a real fork, not an oversight.

Also unspelled: varargs declaration syntax, and where the call-site array's element representation comes from — the entry below.

### A collection parameter erases its element representation · `discrepancy` · `3`

Widths come from `range` and `precision`, and [Numeric Types](Language%20Spec.md#numeric-types) states widths are a guarantee. An array carries those annotations once, so it is homogeneous — but the receiving parameter is spelled bare.

```
define proc sum(List(integer) numbers)
```

`integer x range(0..999)` gives 16-bit elements, bare `integer` gives 32-bit, and both are `List(integer)`. So that signature accepts one representation only, or silently rescales — and rescaling breaks widths-as-guarantee *and* [pass by reference](Language%20Implementation.md#parameter-passing), since it forces a whole-collection copy.

Half fixed by the collection redesign: the element type now has a syntactic home, so `List(integer range(0..999))` is spellable and distinct from `List(integer)`. What remains is monomorphizing over it, which is [blocked on generics](#data-modeling-and-declaration-syntax) — the sized-generic shape in [Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#arrays-fixed-strings-symbolstags-sized-generics), extended from capacity to `(range, f)`.

Note what does *not* need instantiating: [computation expands to 64 bits](Language%20Implementation.md#arithmetic), so there is no per-width arithmetic — only a widening load, a rescale shift, a narrowing store. A body compiles once and specializes its accessors.

### Erased component handles · `pending` · `3`

`Component c` as a parameter needs no hierarchy — a compile-time constraint, monomorphized, so `remove_component` works without dispatch. It does not cover holding a *set* of differently-typed components: save file contents, editor selection, batch of removals.

An array cannot hold them: one stride cannot cover several layouts, and monomorphization only duplicates code that stays homogeneous.

Proposal: heterogeneity only behind indirection, and the language has exactly one — the handle. Component handles are uniform-width and already carry entity plus component identity, so `Component[]` is stride-uniform, no boxing, no padding. Frame-locality free, since a handle cannot be stored or held across a frame.

Conditions the design must keep:

- The constraint bounds the *operations*, not just the type: remove, `has`, whole-copy, serialize — all needing only entity and component id.
- A typed field is reachable only through narrowing (`if c is Health h`). The component set is open, so exhaustiveness is impossible and a default arm is mandatory, unlike `enum`.
- No reflection, no string-keyed access, or [access-set extraction](#systems-scheduling-and-parallelism) becomes incomplete rather than imprecise.

Extraction survives these conditions; the cost is scheduler precision, opt-in.

Blocked on a `ComponentId` type, which belongs to [the core API](#core-api).

### `List` has no operations · `pending` · `3`

[`List(T)`](Language%20Spec.md#collections) has a runtime element count and nothing to read or change it with. Needs reading the count, appending and removing, and a rule for what appending past `capacity(n)` does — failing matches [range violations](Language%20Spec.md#ranges), which do not clamp either.

Spellings are constrained by [no dot-call syntax](Shelved.md#data-modeling-and-declaration-syntax), so these are free procedures over the collection. `count` is also a [query reduction](#queries-and-predicates); reusing the name is the [one clause vocabulary](#queries-and-predicates) idea arriving early rather than a collision.

### String encoding · `pending` · `2`

Open: what encoding do [strings](Language%20Spec.md#strings) use, and may they hold non-ASCII?

Deferrable again. The conflict was that a character count gives no fixed inline size unless the encoding is fixed-width or the field reserves a worst case, which made an inline string's footprint — and therefore its placement — unevaluable. Strings being always external removes the layout dependency entirely; the encoding is now a property of a runtime-owned buffer and nothing in the surface reads it.

Still needed eventually by [slices](#data-modeling-and-declaration-syntax) and by iterating a string, both of which want a per-character type.

### An interned identifier type · `idea` · `2`

[Strings are always external](Language%20Spec.md#strings), so a short identifier in a component costs an indirection. A string is the wrong tool for that case regardless — the need is O(1) comparison and a fixed width, not text.

Shape, if it is real: an index into an intern table filled at the load boundary, so the value is flat-copyable and serializable rather than a pointer. Godot's `StringName` is the precedent for promoting interning into a distinct type instead of leaving it an invisible optimization, which is the same reasoning as [No hidden costs](Design%20Principles.md#no-hidden-costs). Its known failure is implicit conversion to and from text; conversion would have to be a named operation from the start.

To settle first: whether identifiers exist that are not known at compile time. If every identifier is a compile-time set, [enums](Language%20Spec.md#enums) already cover the case — O(1), fixed-width, flat-copyable, with payloads. The case this answers is data-driven content whose IDs arrive at load. If nothing is created after load, the table is frozen and needs no runtime insertion story.

Purely additive, so deferring costs nothing. The fallback if it never arrives is that text in a component is cold data and pays the chase.

### Text accumulation has no construct · `pending` · `1`

[Strings are immutable and there is no concatenation operator](Language%20Spec.md#strings), so interpolation is the only way to build one. Accumulating across branches or a loop is O(n²), or unwritable.

Settled: a growable scratch space with [handle semantics](Language%20Spec.md#data-modeling), appended to with whole strings, producing its final `string` through an explicit named operation rather than a coercion. It is a frame-local tool, not component data — the existing structural validity rule (not storable in a component or file state, not held across a frame boundary) covers it with nothing new to check.

Open: what it is called, how construction, append and output are spelled, whether a capacity argument is a hint or a guarantee, and whether output copies or spends the accumulator.

### The inline/external default threshold · `pending` · `2`

[Storage](Language%20Spec.md#storage) says placement follows capacity when unstated, without saying where the line is. Open: the number, and whether it is contract or mechanism.

Stating it in the [Language Spec](Language%20Spec.md) makes it a promise that cannot be tuned without breaking cost expectations; leaving it to [Language Implementation](Language%20Implementation.md) keeps it tunable but means an author cannot predict what they got, which weakens the low-risk-default argument the design rests on. Deferred deliberately (Joaquin, 2026-09-01).

It must be one constant, identical on every target — a threshold derived from cache-line size would give peers different component layouts, and [schema agreement](Engine%20Core.md#frame-model-and-synchronization) is a premise of the frame model.

### Slices · `pending` · `4`

No way to name a sub-range of a collection or string, and no way to write one procedure that reads either [collection type](Language%20Spec.md#collections). `define proc sum(List(integer) numbers)` cannot accept a `Fixed(integer, 8)`, and [no subtyping](Language%20Spec.md#non-goals) means nothing bridges them. Go, Rust and Odin all answer this the same way: the view is the common currency and both collections convert to it.

Raised from `3` when the collection split landed — it stopped being a convenience and became the only spelling for a procedure over both.

A slice is also what iterating a string should yield — `for c in name` needs a per-character type, and there is no `char`. That half stays blocked on [encoding](#data-modeling-and-declaration-syntax); the collection half does not. Until then strings are not iterable, though they remain valid [membership](Language%20Spec.md#membership-semantics) operands.

### Named-argument separator · `idea` · `1` · `syntax`

`:` names a field at construction (`Weapon(damage: 10)`) and labels a [tuple](Language%20Spec.md#tuples) element. Worth evaluating whether `=` reads better, since the operation is assignment to a named field.

The two sites are not one mechanism: construction resolves names against a declared schema and zero-fills omissions; a tuple literal has no declaration, so labels come from the literal and nothing may be omitted. `:` already carries two meanings, and a decision moves both.

Deferred on whether a map literal is ever added — the other construct that wants `:`, and keeping the colon reserved for it may be worth more than the consistency gained here.

### Value constants · `pending` · `2`

Values like `Vector3.left`. Used in [LoomScript Examples](LoomScript%20Examples.md), unspecified in the language.

Ranges are values, so a named range is the same question asked of `range(...)`. Once settled, `in` should accept a named range wherever it accepts a literal one.

### Are annotations addressable · `pending` · `2` · `syntax`

Annotations are written on declarations and have no existence as operands. Two items ask this from different sides; neither is answerable alone.

*Testing against a declaration's own range.* `integer ammo range(0..999)` has no spelling as an operand, so a test restates the bounds and can drift. Speculative form:

```
if reload_amount in range of ammo
```

Open: what does it mean for a field unbounded on one side? Does `range of` earn a two-word operator when the declaration is usually in view?

*Where the rounding operations live.* `floor`, `round`, `ceil`, `truncate` are unplaced — language operations, or [core API](#core-api) procedures. The second must be expressible by an ordinary signature, and the optional precision argument is the problem: `round(position, precision(2))` passes an annotation as a value.

- Not addressable: precision needs another spelling, rounding is compiler-known, `range of` does not exist, range tests stay manual.
- Addressable: both fall out of one mechanism, and the question becomes what an addressed annotation *is* — value, compile-time constant, or type-level thing.

Review first: the spec spells it `round(position, 2)`, sidestepping the problem but leaving the unit implicit. Intended, or placeholder? It changes the answer.

### Proven presence and flow narrowing · `pending` · `3`

The binding forms are settled and specified ([Component Access](Language%20Spec.md#component-access)). Two things around them are not.

Should the compiler *also* narrow without a binding, so a bare `e.Health` inside `if e has Health` is known infallible? That is flow-sensitive checking — the fact travels from condition into branch, and an intervening call can invalidate it — so it needs purity and access-set information in the type checker. Not rejected; the enum case was decided on syntax, not this cost. Separate from the binding form, and depends on [inferred purity](#systems-scheduling-and-parallelism).

Also unstated: what does a component binding refer to after an intervening call removes that component? Structural changes defer to the frame boundary, so the data survives and the write lands on something about to be discarded. Sound, but "removed but still writable until the boundary" is not obvious and needs writing down.

### Component single-field coercion · `idea` · `2` · `syntax`

A component whose only field is `value` could be read as that field directly — `entity.Position` for `entity.Position.value`. Removes the most repeated noise in practice, since single-field wrappers are the common case. Costs a second access form for one shape of declaration, and an ambiguity wherever the component itself is the intended operand.

### Entity type carrying a component invariant · `idea` · `2`

A proc returning `Entity` says nothing about what it has, so every caller re-checks. A return type meaning "entity known to have these components" moves the check to the boundary.

Output-side twin of [a `where` clause on procs](#data-modeling-and-declaration-syntax) — one question at two boundaries, settle together.

Distinct from absence semantics: absence is a runtime question about whether a value is there, this is a static claim about what an entity has. They meet only where such a proc must also express "found nothing", which is the two combined.

---

## Queries and Predicates

### A query as a form inside a proc, not a `define` kind · `idea` · `4` · `syntax`

`define query` may not need to exist. If a query is a form appearing *inside* a procedure — statement, expression, or both — a named query is an ordinary proc containing one, and the language loses a declaration kind without losing a capability. Under [Compose constructs, not values](Design%20Principles.md#compose-constructs-not-values) the kind does not earn its keyword: it maintains no invariant and adds no matching primitive, which is what separates it from `relationship`.

Costs nothing that was checked for: event attachment, the optimizable `for`/`where` region, and [access-set extraction](Engine%20Core.md#scheduling-and-execution) all survive.

Buys, mostly in problems already open here: [empty-match fallback](#queries-and-predicates) wants a nested query and does not know whether a query is a statement — answered by construction. [Reductions](#queries-and-predicates) needs a query usable where a value is expected. Named queries gain locals, early exit and setup.

Relocates rather than resolves: a query is two shapes, an iteration statement with effects and a value-producing expression with neither. Same fork as [one clause vocabulary](#queries-and-predicates). Still progress — "expression or statement" is answerable, "what kind of declaration" was not.

Take up before [systems](#systems-scheduling-and-parallelism) (`5`, unmade), which asks the identical question about a higher-stakes construct.

Open:

- Does an anonymous query on an event survive, or become an anonymous proc?
- Is nesting a query in another's body permitted? What does it mean for join ordering?
- Does `do` stay the only place data may be modified, once a query can also be an expression?

### The documented `with`/`where` boundary is not the one that costs · `discrepancy` · `4`

[Clauses](Language%20Spec.md#clauses) presents the split in cost terms, then disclaims that it constrains the compiler. Both are true under the intended model: `with` and `where` form one declarative region the compiler may reorder freely — servicing `distance(...)` from a spatial partition, say — while `do` is imperative and largely opaque.

So the load-bearing boundary is `where` against `do`, and the spec does not mention it. Hoisting a predicate from `where` into an early exit at the top of `do` looks cosmetic and silently forfeits acceleration, converting a partition lookup into a full scan — an implicit cost of exactly the kind the design forbids.

A second cliff sits inside `where`: if acceleration depends on recognizing predicate shapes, then equivalent-but-unrecognized predicates degrade to per-entity scans with nothing in the syntax to distinguish them. Either specify the recognized set, or give `where` a restricted grammar.

Spatial partitioning for `distance(...)` is a candidate to evaluate against [No general indexing or materialization](Design%20Principles.md#no-general-indexing-or-materialization), not a violation of it.

### Reductions · `discrepancy` · `4`

Pulled from the spec, needs further work. A query ending in a reducer rather than a `do` block produces a value usable anywhere a value is expected:

```
define query count_dead_units 
for unit with Unit, without Alive
count unit
```

`count` and cardinality reductions cost no extra scan; `sum`/`avg`/`max_by`/`min_by` visit every match and cost what the hand-written scan costs. No materialized or orderable result-set type — grouping, sorting and top-N stay outside the query language.

### Incrementally maintained reductions · `pending` · `2`

Can `sum`/`count` over a live query be updated on write rather than rescanned on read? Needs the prior value exposed on a `changed` event, which is undesigned. Sketch: hook the existing dirty-bitmap change detection and update a running accumulator, rather than new infrastructure.

Deferred, not solved — access to previous values is a requirement on the ECS design itself, and belongs in that requirement list.

### Query amortization and update rates · `pending` · `3`

Budgeted "process N per tick, resume where it left off" work. Coroutines are disallowed, since suspending mid-iteration holds call-stack state across a frame boundary. Replacement is a resumable cursor: position and accumulator as game-tier state, each resume a fresh call-stack scope.

Staggered update rates (distant entities every other frame) are simpler and separate — bucket by `entity_id % K`, one bucket per frame, no suspension at all.

No syntax for either. Open: is the cursor author-visible state, or a query-level annotation?

### One clause vocabulary over entities and collections · `idea` · `3` · `syntax`

`for` introduces two unrelated constructs: `for i in range(0..n)` walks a sequence, `for e with Position` opens a query. Same keyword, different cost model, no shared grammar. Prerequisite for growing the clause vocabulary at all.

- *Unify.* Extend `where` and the [reductions](#queries-and-predicates) to plain collections, so `for item in inventory where item.weight > 10 do` is the same construct. One shape for both worlds; `count`/`sum` over an array stops needing a second spelling.
- *Split.* Different keywords. A query is a reorderable join; a loop is an ordered walk with a defined trip count, and [No hidden costs](Design%20Principles.md#no-hidden-costs) says a reader should not have to check the operand to know which.

[Empty-match fallback](#queries-and-predicates) describes the same ambiguity from the other end, treating `for` meaning loop-or-query as a cost rather than something to lean on. Settle together.

Open:

- Is `where` over a collection honest? Reorderable region over entities, per-element test over an array — two cost models, one spelling.
- Is iteration order guaranteed? Arrays have one, queries don't.
- Is result size the admission rule for further clauses? Fixed-size (reductions) free; variable-size (`order by`, `group by`, `limit`) needs a buffer and a spelling that shows it. Consistent with [No general indexing](Design%20Principles.md#no-general-indexing-or-materialization) and [GroupBy](Shelved.md#queries-and-predicates).
- Do `in` and `with` alone distinguish them at a glance?

### Empty-match fallback, and asymmetry in `for` clauses · `pending` · `4` · `syntax`

No spelling for: run a body per match, run something else once when an entity matched nothing. Today needs a manual flag set inside the iteration and tested after — noise, and easy to get wrong by applying per-non-match what was meant once.

An `else` block covers it, meaning "the body never ran" (Jinja's sense, not Python's).

The blocker is not the keyword. A [`for` clause](Language%20Spec.md#the-for-clause) is symmetric — a flat set of bindings the compiler orders freely — so `else` can only mean "the whole query produced nothing". Per-entity fallback needs an outer and an inner binding, which the clause cannot express.

- *A query nested in another's `do` block.* No new clause grammar, and a real outer body. But whether a query is a statement is unspecified, as is an inner binding referencing an outer one, and `for` then means loop or query depending on `in` versus `with`.
- *Per-level `do`/`else` blocks in one query.* One construct, but a second optional block per level, and nesting is distinguished from cross-product by punctuation alone — a comma between bindings versus a repeated `for`.

Either way binding order becomes semantic and the compiler loses join-reordering freedom. That is a cost model change, so contract rather than mechanism, and it works against the freedom [the `with`/`where` boundary](#queries-and-predicates) relies on.

---

## Relationships

### Payload storage on symmetric relationships · `pending` · `3`

Where payload data lives on symmetric or many-to-many relationships, which have no single owning side.

### Quantified negation over a relationship or sub-match · `pending` · `3`

"No entity related to this one satisfies X" — a real gap, no syntax chosen.

### Transitive traversal · `mechanism` · `3`

Needs a real graph walk, and is the one query construct whose cost is genuinely runtime-dependent rather than bounded by the match set. No depth bound decided; see [bounded execution](#errors-and-control-flow). TODO in the spec's [Relationships](Language%20Spec.md#relationships).

### Ephemeral and exclusive relationships · `pending` · `2`

TODO in the spec's [Relationships](Language%20Spec.md#relationships), undesigned.

### Direct iteration over a bound relationship's targets · `pending` · `2` · `syntax`

Iterating a relationship outside a query — given a held `Entity`, walking its `Children`. Sketched as reusing `for ... in`, not finalized.

### Wildcard / `any` relationship terms · `mechanism` · `2`

Presence-only bitmap checks, no target materialization — cheapest possible form, and a distinct codegen path from named targets, which compile to forward lookups (a direct index or pointer chase, not a general join). Unused named targets can be optimized away statically.

---

## Events and Change Detection

### Change-tracking surface · `pending` · `4`

[Change Tracking](Language%20Spec.md#change-tracking) says only that `changed(Component)` fires on the frame a value changes. Unspecified: granularity (component or field), whether storing the same value counts, how it interacts with `with changed` in a `for` clause, and when the flag clears relative to system order.

### Custom event declaration · `pending` · `4` · `syntax`

Declaration syntax for game-level events (`player_joined`) beyond built-in `tick` / `changed` / `load`. Parked on it: binding a parameterized event without the trigger's parameter colliding with a `with`-bound name — `on dead(unit)` alongside a bound `unit`.

### `changed(Component)` has no defined meaning on a non-owning peer · `discrepancy` · `4`

Remote state arrives as a raw chunk write, not a script-initiated mutation. Diffing received chunks to fire `changed` is a recurring per-frame cost, against no-implicit-costs. Not firing makes reactive code behave differently on owning and remote peers, which is the networking awareness the design removes. The language cannot stay silent — `changed` is author-visible.

### Periodic scheduling has no construct, and the obvious spelling is wrong · `pending` · `4`

"Every N seconds" is ubiquitous and unsupported. By hand it is an accumulator against a period, and the natural spelling — modulo of accumulated time — is silently wrong, true on nearly every tick rather than once per period. Correct needs an explicit crossing test against the previous tick's value, which is neither obvious nor discoverable. A pit of failure in the sense [Pit of success](Design%20Principles.md#pit-of-success) rules out: reads correctly, behaves wrongly, no diagnostic.

Two levers, not exclusive:

- A tick-integer timer in the core API makes the modulo form exact by removing the float error — see [Engine API](Engine%20API.md#timing).
- A language-level periodic trigger alongside `tick` removes the accumulator, but must answer what happens when a period is shorter than a frame, and whether missed periods coalesce or repeat.

---

## Errors and Control Flow

### Bounded execution · `contradiction` · `3`

Loop and recursion limits for determinism: flagged as needed but undesigned, with no GC pause to blame instead. Transitive relationship traversal is the first construct with genuinely runtime-dependent cost and no max-depth safeguard, which makes the gap concrete.

[Previous Iteration Syntax](Previous%20Iteration%20Syntax.md#error-handling) answers it cheaply — a runtime execution cap that halts when exceeded, no proof-of-termination requirement, no annotations. Adopt or reject explicitly rather than leaving it open.

### Halt unwind granularity · `pending` · `3`

[Error Handling](Language%20Spec.md#error-handling) says `fail` halts execution, not how far the halt travels. The previous iteration was precise: unwind to the nearest engine-called entry point. A tick function aborts the tick; a query callback aborts that entity's iteration and the rest continue; a cursor resume aborts that resume. That granularity is what makes [Fail fast, keep the engine resilient](Design%20Principles.md#fail-fast-keep-the-engine-resilient) concrete, and it draws a line the spec does not: expected absence is never a halt.

The previous iteration kept the boundary unambiguous by forbidding a query from invoking another. The spec now allows named queries to be invoked from anywhere, so the question that ban avoided is live: a halt inside a nested query has no defined stopping point — inner entity, outer entity, or whole trigger?

Naming: previous iteration used `halt`, communicating only that the current entry point stops. The spec uses `fail`.

### Intrinsic fallibility · `idea` · `4`

Propagation and recovery are unspecified. Supersedes an earlier proposal (Jose) of automatic upward propagation with a catch keyword — this delivers the propagation and drops the keyword, so they are not alternatives.

Failure is a property of an expression, not a construct layered over calls. Anything the compiler knows can fail — absent component, index out of bounds, division by zero, dead handle, relationship with no target, value outside a declared range, narrowing coercion — is *fallible*, and type-checks only inside a context that handles it. `if` is that context. No catch keyword, no new syntax; the feature is subtraction.

Inferred by the same pass as [purity](#systems-scheduling-and-parallelism): an unguarded fallible expression makes the proc fallible, so calling it is fallible. Propagation real but typed, every frame opting in visibly.

**Derived versus authored** is the line. Derived is catchable; `fail`/`assert` stay terminal, or a caller could swallow an invariant violation. Also settles what [halt unwind granularity](#errors-and-control-flow) needs.

Declared ranges make it affordable: `a / b` infallible when `b` excludes zero, arithmetic infallible when the result fits. Overflow stops being a separate concept. A required guard signals an under-specified domain, and the remedy is to state the range.

Collapses `has`: a fallible expression in `where` filters the entity out, so presence and value predicates become one rule, `with` its accelerable form.

Not adoptable independently of range refinement — weak refinement means guards proliferate. That analysis has to be specified, not just implemented.

Open:

- Absent versus false become indistinguishable when filtering. Accept the silent skip?
- What is the infallible escape where refinement can't prove safety? Saturating or wrapping operators?
- Does anything bind on failure, including multi-return tuples?
- Partial mutation from a proc that wrote before failing. See [implicit transactional mutation](#errors-and-control-flow).

### Implicit transactional mutation · `idea` · `3`

Counterpart to Verse's `<transacts>` rollback, from the opposite direction: Verse needs a declared effect and general transactional memory, where the compiler here already sees every ECS write ([access-set extraction](#systems-scheduling-and-parallelism)). If every mutation in a scope is known statically, its writes can be buffered and applied atomically on successful exit, structural changes deferred to a frame boundary.

Two properties follow: a halt leaves no partially mutated world, making [Fail fast](Design%20Principles.md#fail-fast-keep-the-engine-resilient) a real guarantee rather than best effort and constraining what [halt unwind granularity](#errors-and-control-flow) must specify; and deferred structural change removes the mid-iteration invalidation hazard handle stability currently absorbs.

Not obviously affordable — buffering is a copy and a commit pass the author did not ask for, exactly what [No hidden costs](Design%20Principles.md#no-hidden-costs) forbids, so the analysis must first establish that the buffer is bounded and statically sized.

Open:

- Is the scope the query body, one entity's iteration, or the trigger?
- Do reads within a scope observe its own uncommitted writes?

### Scope-escaping keywords · `pending` · `3` · `syntax`

Only `return` exists. Loops cannot break or skip, a query body cannot advance to the next match, and a `match` arm cannot say it deliberately does nothing. One pass over every escaping form, not a keyword per context:

- Leaving a loop (`break`).
- Next iteration (`continue`, `skip`).
- Next query match — same idea, different scope.
- Explicit no-op (`pass`), escaping nothing, so a reader can tell a deliberately empty branch from an unfinished one.

The last two are distinct needs one keyword should not serve: advancing is the early exit proper; the no-op has no control-flow effect and is mostly wanted on a `match` arm.

Open:

- Can one keyword serve loops and query bodies, given their costs differ?
- Is the no-op worth a keyword when a comment conveys it?
- May any form cross a query body's boundary? [Empty-match fallback](#queries-and-predicates) and the `where`/`do` split both depend on what the body may do, and an early exit inside `do` silently forfeits acceleration.

When settled, update the [Enums](Language%20Spec.md#enums) example, whose `when Nothing` arm carries a `| no-op` comment where a keyword would be clearer.

### Alternative ternary syntax · `idea` · `1` · `syntax`

Condition first (Jose, Joaquin). `x = a if condition else b` sandwiches the condition between the two values, so reading order and evaluation order disagree — the reader meets `a` before the condition deciding whether `a` is the answer.

Familiarity does not defend the current form: only Python is subject-first, while C#'s `condition ? a : b` and Lua's `condition and a or b` are condition-first, so two of the three audiences already expect the condition to lead.

```
x = if condition then a else b
```

Condition-first, evaluation order, plain English, reuses `if`/`else`. Only new word is `then`, which [pipe syntax](Shelved.md#data-modeling-and-declaration-syntax) also wanted — now shelved, so it is free.

Blocks nothing.

---

## Compilation and Backend

### Host embedding API · `pending` · `5`

What the engine exposes to guest modules, and how capabilities are granted. Unwritten. Blocks [asynchronous operations](#storage-and-memory-layout) and the I/O surface below.

### Reload semantics for live state · `pending` · `4`

[Hot reload](Runtime%20&%20Deployment.md#hot-reload) swaps a module's Wasm object; what happens to entities and component data defined by that module is undefined.

File-level variables are [Unmanaged](Engine%20Core.md#memory-tiers), so the swap discards them and they return zero-initialized. Whether that self-heals turns on: does `load` re-fire on reload? Least surprise says yes, and a table populated in `on load` needs it to. But the world already holds the entities the first firing created, so re-firing duplicates them unless this entry says what happens to them. Answer both together.

### Observable agreement between backends · `pending` · `3`

Must AOT and interpreted backends agree observably — execution bounds, numeric edge cases — or may they differ? Fixed-point removes most float divergence risk, but bounded execution is decided per backend unless pinned here.

### I/O surface · `pending` · `3`

Input, audio, asset loading, save files, network transport. Not excluded, just unspecified as host-exposed capabilities. Blocked on the host embedding API.

### Schema-tagged saved data · `pending` · `3`

Peers pre-agree on all data schemas, so nothing on the wire needs a build-independent identifier. Saved data breaks that assumption, since it outlives the build that wrote it.

Settled: the schema travels with the data — a save stores what it was written against, and load remaps when they differ. Version skew handled once, in the save path, rather than by freezing identifiers across the language.

Undesigned: what a stored schema contains, which changes are remappable and which are hard failures, whether remapping is automatic or author-directed, and whether the same mechanism covers a hot-reloaded module. Blocked on the storage model, since what a schema must describe depends on it.

### Load-time branch elimination is an optimization, not a guarantee · `discrepancy` · `2`

Deliberate — evaluating the condition at run time is equally correct, so promising elimination would over-constrain the backend. But an author gets no language-level assurance that a branch behind an absent module costs nothing, which is the implicit cost [No hidden costs](Design%20Principles.md#no-hidden-costs) rules out.

Direction: tooling rather than spec — surface what was stripped and what survived, per [Show the machinery in motion](Design%20Principles.md#show-the-machinery-in-motion).

### Const-eval of pure procedures · `idea` · `2`

[Constants](Language%20Spec.md#constants) allows only literals and other constants, so any computed value becomes a hand-computed magic number. Once [purity is inferred](#systems-scheduling-and-parallelism), a pure proc called with constant arguments is itself a constant, and the load-time evaluator already exists for load-time conditionals. Lookup tables, precomputed curves and sizes from a formula become expressible with no new mechanism.

Same inference-plus-optional-annotation shape as purity: implicit wherever arguments are constant, with an annotation to pin intent so a later edit that makes it runtime-dependent fails compilation rather than silently becoming a per-execution computation.

Open: interaction with the rule that constants depending on a load-time conditional cannot determine data layout, since a const-eval'd proc widens what can reach an array bound; and termination, since the call must complete at the load boundary — ties to [bounded execution](#errors-and-control-flow).

### Bundled source produces private types · `pending`

Sharing source between modules by local bundling, without registering a module, yields a distinct private type per bundler — by design, not a defect. Sharing a real type requires a module dependency. Unstated in [Program Structure](Language%20Spec.md#program-structure), and the kind of rule discovered the hard way if left implicit.

---

## Core API

### The core API surface is unspecified · `pending` · `4`

Scripts already depend on engine-provided types and procedures no document describes — vector types and their value constants, RNG, elapsed tick time, geometric predicates, ordinary math. [Engine API](Engine%20API.md) holds the boundary and the areas; almost none of the contents are settled.

Distinct from the [host embedding API](#compilation-and-backend), which is about capabilities the host grants. The core API is present in every deployment.

One member is already load-bearing: `ComponentId`, a runtime value naming a component type. Needed by [erased component handles](#data-modeling-and-declaration-syntax) and by data-driven structural changes (save files, network messages, editor selections), and it is what lets a deferred removal be recorded without holding the component. An identifier, not polymorphism.

### Timer primitive · `mechanism` · `3`

Proposed: a starting tick number plus a duration in ticks. Fixed size, no indirection, so it passes [the flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) with no taint and sits in a component directly.

What earns it: read-only until it fires. A countdown writes every tick on every entity holding one, producing sync traffic and change-detection churn on data nobody asked about; start-plus-duration is compared, not mutated. Integer ticks also remove the float error behind [periodic scheduling](#events-and-change-detection).

Hazard to resolve first: an absolute start tick is only meaningful against an agreed tick origin. Copied to a peer whose counter differs it silently yields the wrong deadline, and [Transparent networking](Design%20Principles.md#transparent-networking-and-serialization) promises the author never thinks about that. A countdown survives resync; start-plus-duration does not. Same question for a hot-reloaded module.

Open regardless: is the authored surface in seconds, converted at load? Are one-shot and repeating one construct or two?

---

## Spec Consistency

### Range violation: which build halts where · `pending` · `3`

Settled in [Ranges](Language%20Spec.md#ranges): never wrap, halt on out-of-range writes, clamp only via explicit syntax. Not settled: which range is enforced in which build.

- *Debug halts over the declared range, release over the representable range.* Conventional and cheap in release, but the two builds are different programs — a value outside `range(0..100)` but inside a signed byte survives in release and halts in debug.
- *Warn over the declared range, halt over the representable range, in all modes.* Build-independent.

The second is worth its weight because of networking: a debug peer and a release peer diverging on the same input is a desync, not a debugging inconvenience. Build-dependent halting makes the declared range an invariant in one build and a hint in the other.
