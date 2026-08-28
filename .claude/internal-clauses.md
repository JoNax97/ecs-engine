# Internal clauses

Agent-managed. Not part of the spec set, not written for a third-party reader.

This file holds the *why* of each design decision: dependency edges between decisions, premises a rule leans on, and consequences that would break if a decision were reversed. The specs state rules; this states what those rules are load-bearing for.

Format: one edge per bullet, `A <- B` meaning "A exists because of / depends on B". Grouped by the decision being justified. Cite the doc section so an edit can find its rationale.

Living artifact. Read it before any design task, and update it in the same pass that changes a doc: new decision, new edges; reversed decision, edges revised or struck. A **Deferred consistency** section at the bottom holds edits already known to be owed to the docs, waiting on a decision that has not been made yet.

---

## Engine Core

**Flat-copyable rule** (`Engine Core.md#the-flat-copyable-rule`)
- <- Frame model: synchronization transfers memory blocks as opaque byte ranges, so anything reachable inside a component must survive verbatim copying to another address space. Reverse the frame model and this rule loses its basis.
- -> Language-level rule that a field inside a `define`d type must state its storage class (`Language Spec.md#storage`). The spec states the rule; its origin is here.
- -> Enums must have declaration-fixed size, which is why enum payload layout is largest-variant-plus-discriminant (`Language Implementation.md#enum-payloads`).
- Shares its taint implementation with load-time constant taint (`Language Implementation.md#load-time-constant-taint`). Two rules, one mechanism — change one and check the other.

**Storage constraints** (`Engine Core.md#constraints`)
- Blind-copyability <- the whole point of the memory-tier split; the tiers exist to protect it.
- Handle stability <- rules out archetype storage as stated; bitmap storage satisfies it structurally. This is the live tiebreaker between the two candidates.
- Partitioning follows ownership/serializability <- a block cannot be blind-copied in one direction if ownership varies within it. Same mechanism is expected to cover streaming, partial loads and interest management.
- Static addressability <- assumed by access-set extraction and by `where` predicates; both take a field as offset-and-width at any depth.

**Component flattening** (`Engine Core.md#component-flattening`)
- -> Nested-field granularity in access-set extraction comes free.
- -> `value` nesting costs nothing at run time, which is what makes values a free abstraction rather than a structural choice.
- -> The taint mechanism already carries a field path; flattening turns that path into an offset.

**Access sets inferred, never declared** (`Engine Core.md#scheduling-and-execution`)
- <- Reverses the previous iteration, which required per-query read/write declarations. Inference is what makes parallelism a checkable property rather than an author's unchecked claim.
- Blocked on: the analysis pass itself is unwritten, and everything about scheduling assumes it.

**Frame model premise** (`Engine Core.md#frame-model-and-synchronization`)
- Load-bearing for: the flat-copyable rule, `non_serialized`, bit packing, and `Design Principles.md#transparent-networking-and-serialization`. It is recorded in the doc as a bare statement; this is the list of what falls over without it.

---

## Language Implementation

**Unbiased numeric representation** (`#integers`)
- <- Zero-initialization. Storing `range(-10..100)` as `v + 10` would put logical zero at bitwise 10, breaking zero-init and adding a correction to every operation. Identical logical and bitwise zero is what keeps entity creation a memset.

**Unified numeric representation** (`#unified-representation`)
- Justification, removed from the doc: this removes a special case rather than adding one. Mixed-precision arithmetic already needs a scale-reconciliation rule, so folding `integer` in makes int-with-decimal an instance of that rule instead of a separate conversion path.
- The surface split survives because overload resolution and declared author intent both depend on it.

**Two-pass load-time checking** (`#load-time-elimination`)
- <- A single skip-if-false walk would let code behind a disabled optional import rot undetected. That is the whole reason the cheaper pass is rejected; if optional imports ever go away, so does the constraint.
- The elimination-is-not-a-guarantee gap wants a tooling answer (surface what was stripped), not a spec guarantee — pinning it in the language would over-constrain the backend. Tracked in `Pending.md#compilation-and-backend`.

**Taint mechanisms** (`#load-time-constant-taint`, `#flat-copyable-taint`)
- One implementation, two rules. Flat-copyable taint reuses the previous iteration's struct-tier inference wholesale, including storing the offending field path at declaration time.
- The stored path doubles as the field offset under component flattening.

**Incremental compilation** (`#incremental-compilation`)
- <- Hot reload (`Runtime & Deployment.md#hot-reload`). The stable-linkage requirement exists only to make single-module recompilation viable.

**Query evaluation reuse claims** (`#reductions`, `#codegen-notes`)
- `count` and cardinality reductions require no new machinery: population counts and relationship counters are already maintained by the storage layer.
- Relationship equality requires no new infrastructure: it reuses the backlink bookkeeping that keeps mutual relationships in agreement.
- Monomorphization is affordable for the same reason a per-label bitmap is: enum labels are a small closed set.
- All three are instances of `Design Principles.md#no-general-indexing-or-materialization` — a fast path qualifies only when it mounts on infrastructure the engine already maintains.

**Inferred binding representation** (`#inferred-bindings`)
- `f = 17` for a `let` decimal <- `precision(n)` caps at 5 (`Language Spec.md#numeric-types`), which makes 17 the widest fractional width any declaration can name. The two numbers are one decision; move either and the absorption guarantee breaks.
- The cap itself <- Wasm has no widening 64x64 multiply, so a `2f` intermediate must fit in 64 bits. At `f = 17` that leaves 29 bits of integer part; at `f = 24` it leaves 15, which ordinary position math overflows.
- Rejected: synthesizing the wide multiply, and using `v128`. Both cost the single-artifact property, since wasm3 implements neither i128 nor SIMD (`Runtime & Deployment.md#execution-backends`).
- -> Reopening the cap depends on static range inference over `(range, f)` deciding per-expression whether a product fits. Same lattice as width inference; not designed.
- Round-to-nearest on rescale <- truncation's error is directional, accumulating linearly rather than cancelling. Toward-zero is also the most expensive of the three modes in fixed point, since an arithmetic shift floors and negatives need a sign-dependent bias.

---

## Language Spec

**Explicit declaration** (`#variables`)
- <- Closes the pit-of-failure where a misspelled name silently declared a new binding.
- `let` carries no annotations <- it means "representation does not matter", which is only honest where the generous representation is free. That is true of a stack slot and false of storage.
- -> `let` is banned at the top level. Same premise: file state is laid-out storage, so the generosity has no basis there. Reverse the premise and the ban goes with it.
- File-level variables are declared like fields, but bare variable-size data is dynamically backed rather than annotated, because `dynamic` opts a *field* out of inline storage and there is no enclosing layout at file scope.

**File state is non-persistent** (`Engine Core.md#memory-tiers`)
- <- Unmanaged memory sits outside every memory block, and the frame model synchronizes memory blocks. Non-sync and non-serialization are consequences of the tier, not separate rules.
- Carried by scope rather than a keyword <- the failure modes correlate with misuse. A genuine cache is rebuildable, so reload wiping it is invisible; state that was secretly authoritative breaks loudly on the first reload.
- Precedent is uniform: Bevy splits `Resource` from per-system `Local`, Unity DOTS keeps derived state in `ISystem` fields and authoritative state in singleton components, flecs splits world singletons from per-system `ctx`.
- -> When systems become first-class, variables stay module-level. A system is not addressable, so `System.variable` would make it addressable through the back door.

**Casing convention** (`#identifiers`)
- Component access keeps the type's own casing <- it is the same symbol written in `with Health`, `create Entity with Health(...)` and `if e has Health`; lowercasing it only in access position would make one symbol change case by context.
- It also marks where the cost is: component access is a keyed lookup that can miss and halt, while field access is a static offset under `Engine Core.md#component-flattening`.
- Advisory, not compiler-enforced. Casing does not prevent collisions; what does is that a proc may not take a type's name (`#procedure-overloading`).

**ASCII identifiers** (`#identifiers`)
- <- Cost avoidance, not semantics. Unicode identifiers require NFC normalization and confusability handling — otherwise `é` as one codepoint and `e` plus a combining accent are different names that render identically, and Latin `a` and Cyrillic `а` are indistinguishable on screen. That is machinery bought to fix a problem that declining Unicode does not have.
- Does *not* rest on the casing convention. A caseless script (CJK, Arabic, Hebrew) cannot express the PascalCase/snake_case split, but since casing is advisory that argument only ever reached style, never validity.

**One bracket form for three roles** (`#basic-syntax`)
- Field lists, construction and calls all use `()`. The previous iteration split them — `{}` for construction, `()` for calls — to avoid ambiguity when a type and a proc share a name.
- Not carried <- `define` marks declarations, and no overloading across the type and proc namespaces, so resolution is unambiguous without a second bracket form. Reverse either premise and the split has to come back.
- Divergence from the previous iteration is deliberate, not an oversight.

**No dot-call syntax** (`Shelved.md#data-modeling-and-declaration-syntax`)
- -> `.` means exactly one thing: reaching into data. A reader never has to ask whether a dotted name invokes something.
- -> The casing convention stays advisory. Dot-sugar on an entity would have needed a lookup order between component types and procedures, or would have made casing compiler-enforced.
- Does *not* weaken the traits argument: overloading alone covers "one name, many types" (`Language Spec.md#procedure-overloading`). Dot-sugar was ergonomics, never load-bearing for it.
- Cost: nested calls read inside-out. If that becomes a real pressure the answer is a threading construct, not dot-sugar, so `.` keeps its single meaning.

**Non-goals section** (`Language Spec.md#non-goals`)
- Purpose is calibration, not justification: a reader arriving from C# or Rust learns the shape of the language before the syntax. It is not a rationale list — the *why* stays in `Shelved.md` and here.
- Entry condition: only **settled** absences. `null`, exception propagation and threading are excluded because their entries are still open in `Pending.md`; listing them would state a decision that has not been made.
- "No asynchronous execution" is admissible despite the async mechanism being undesigned, because the synchronous property is settled independently of which mechanism is chosen (`Pending.md#storage-and-memory-layout`, asynchronous operations).
- Not the home for small feature absences (unary `++`, operator overloading, dot-calls, macros). Those are lookup answers, already inline where they matter, and would turn the section into a dumping ground.
- Load-bearing negatives do **not** live here. A rule a checker enforces goes where it bites, as part of the positive rule it constrains — otherwise it reads as trivia and gets missed.

**Tuples** (`Language Spec.md#tuples`)
- Stack-only <- a storable tuple would need a position under the flat-copyable rule, and would then be a `value` without a name. Keeping them off `define`d types removes the storage, schema and taint questions outright rather than answering them.
- No annotations on elements <- annotations attach to declarations and a tuple literal is not one. Consistent with `let` taking none (`#variables`). This is also a second reason a tuple cannot be a component field: a `string` or array inside a `define`d type must state its storage (`#storage`) and a tuple has nowhere to state it.
- Cap of four <- makes ordinal accessors complete: `first` through `fourth` cover the whole space, so unnamed tuples never need `.0` and `[]` keeps its single meaning (`#basic-syntax`). Past four the better option is a `value`, which costs one line. Reverse the cap and positional access has to come back.
- Names documentation-only <- the `signature` precedent, matching by type and order (`#signatures`). Consequence: named and unnamed tuples are the same type, so the no-mixing rule constrains *literals*, not types.
- Implicit construction, never implicit deconstruction <- the asymmetry is what kills the spread/nest ambiguity. Under it `f(10, 5)` and `f((10, 5))` are two different types and nothing flattens, so no call-site text means different things depending on the callee. Ranking construction as a coercion is what lets an exact parameter match win over it (`#procedure-overloading`).
- Deconstruction is an explicit construct <- without that, "never taken apart implicitly" would contradict `let div, mod = divmod(10, 3)`, which the spec already had. Same status as `_` in `#discards`.
- Not iterable <- a heterogeneous sequence can only be walked by compile-time unrolling, whose body must typecheck per element type. That is generic-code machinery and would make tuples depend on `Pending.md#data-modeling-and-declaration-syntax` generics.

**Heterogeneity only behind a handle** (`Language Spec.md#non-goals`, no universal type)
- <- A layout constraint, not a type-system one: one stride cannot cover several layouts, so a contiguous buffer holds mixed types only via indirection or a discriminant plus largest-variant padding. Monomorphization does not help — it duplicates code and each copy is still homogeneous.
- <- The language has exactly one indirection, the handle (`#data-modeling`), and handles are uniform-width by construction. So `Component[]` is admissible where a mixed value array is not, with no boxing and no padding.
- -> This is what rules out `any`, and what sends the two heterogeneous-sequence cases — component packs and `print` — to `Pending.md#data-modeling-and-declaration-syntax` rather than to a universal type.
- -> `enum` remains the sanctioned *closed* heterogeneous form: largest-variant layout, flat-copyable, no indirection. The rule bans open heterogeneity, not tagged unions.
- Stated as an expectation in `#non-goals` and enforced per-construct where it bites. Deliberately not written as a standalone positive rule in `#data-modeling` (Joaquin, 2026-08-28) — the spec states what the language has, and every construct that could violate this already carries its own rule.

**Array literals use brackets** (`Language Spec.md#arrays`)
- <- An unnamed tuple literal and a parenthesized homogeneous list are the same text. Disambiguating by homogeneity would make a literal change category when an element's type changes, which is the context-dependence the rest of the design avoids.
- <- `[]` already means "N of this type", so the literal matches the declaration form. Cost accepted: `[` now opens a literal as well as closing a declaration bound.
- No separate list type <- an unnamed, homogeneous, indexable, iterable sequence is an array with a literal-inferred bound. Naming it something else would be a second spelling for one construct.

**Values and handles** (`Language Spec.md#data-modeling`)
- Two behaviours, not three. Entities, components and future resources are all handles; everything else is a value. Reference semantics for handles are meant to read as classes do in a managed language, with the runtime owning the memory instead of a general arena.
- Supersedes the provenance-inferred backing idea (previous iteration). That version made the destination of a write a fact about where an identifier came from; carrying it in the type makes it a fact about the type, which is what `Design Principles.md#no-hidden-control-flow-no-implicit-costs` asks for.
- Validity is structural, not checked: a handle cannot be stored in a component or file state, nor held across a frame boundary, so it can never refer to data that is gone. Same shape as the signature rule — the reference exists only where it cannot be saved.
- -> Settles the parameter question. A component parameter is a view because every component identifier is; a value parameter is a copy. What the user learns is the value/handle split, which is the ECS distinction they already need — not a by-value/by-reference calling convention.
- -> Deferred structural change (create into a temporary region, move at the boundary; delete deferred to the same point) is what makes the guarantee hold, and it arrives as a consequence rather than as a feature. Ties to `Pending.md#errors-and-control-flow`, implicit transactional mutation.

**Bindings are immutable** (`#bindings`)
- Covers parameters, loop variables, query bindings and `is` bindings with one rule, rather than four answers. The narrowing case forces it: `is Heal heal` binds a live reference, so `heal = other` would be ambiguous between rebinding and writing through.
- -> Parameters are always passed by reference, and a value parameter is copied only where the body writes into it (`Language Implementation.md#parameter-passing`). Writing into the parameter's own storage is the only channel through which a callee could observe how it was passed, and immutable bindings plus no reference parameters and no closures leave it as the only one. Reverse any of those and the copy decision stops being static.
- Constrains the identifier, never the data. `target.Health.current += damage` and `heal.amount = 0` stay ordinary writes.
- Cost is confined to parameters: no `arg += 1`, and with no shadowing form and identifiers unique per scope, deriving a value needs an explicit `let`. Accepted — the new identifier names what the value is.
- Precedent: Odin forbids it, C/C#/Java/Go/JS allow it. Odin's reasoning is the one that transfers, and it is stronger here because the escape routes it depends on were already closed for other reasons.

**Proven presence** (`#component-access`)
- One rule across both contexts: component access is infallible exactly where a construct has proven presence — `with` in a query, `has X x` in an expression. Bare `e.Health` stays legal and fallible.
- `has X x` is not merely shorter than `has X` plus `e.X`. It makes the access infallible *without* flow-sensitive checking, because the binding's validity comes from the construct that created it rather than from a fact carried across statements.
- -> No fact to invalidate. An intervening call that might remove the component cannot make the binding illegal, which is what a narrowing checker would have to track through purity and access-set information.
- Both spellings stay. The old bare-`has` form is unchanged, and the stutter in `has Health health` is accepted as unavoidable.
- Open, and deliberately separate: whether the compiler *also* narrows bare access inside a guard (`Pending.md#data-modeling-and-declaration-syntax`). The enum case declined narrowing on syntax grounds, not on checker cost, so that door is not closed.

**`in` takes a range and nothing else** (`#ranges`)
- <- Cost, not syntax. `x in range(0..10)` is two comparisons; `x in array` is a linear scan. Same three characters, unrelated cost, which is what `Design Principles.md#no-hidden-control-flow-no-implicit-costs` forbids. Array membership is a call, so the work is visible where it is paid.
- Precedent splits on exactly this line. Odin allows `in` only on maps, bit sets and ranges — all O(1) — and requires a procedure for slices. Rust, Swift, C# and Go have no membership operator at all. SQL's `IN` takes a literal list, whose length is visible in the source. Python is the counterexample: `x in list` is O(n) and `x in set` is O(1), identical to read, and a known trap.
- -> `for i in range(...)` and `if x in range(...)` are one operand shape in two positions, rather than one keyword doing two unrelated jobs.
- Literal ranges only for now; ranges are values, so a named range follows once value constants are settled (`Pending.md#data-modeling-and-declaration-syntax`).

**Negated presence and narrowing** (`#operators`)
- Single operators, not `not` applied to a result. That is what keeps them from being a second spelling of an existing composition — the objection that shelved dot-sugar.
- `has no` and `has not` are both accepted, for the same operator, because English needs both: `has no` before a noun (`has no Shield`), `has not` before a past participle (`has not Moved`). Tags are frequently participles — `Moved`, `Dead`, `Stunned` — so neither form covers every operand. This is the one place two spellings were accepted deliberately, and it is grammar rather than preference.
- `no` is reserved. Casing is advisory, so a component could legally be named `no`, which would make `e has no` ambiguous. `not` was already reserved as the boolean operator.
- <- Precedent is direct rather than analogical: SQL `IS NOT NULL` / `NOT IN` and Python `is not` / `not in`, and SQL is a stated inspiration.
- -> Removes a precedence question. `not target has Shield` needs `has` to bind tighter than `not`; `target has not Shield` has nothing to get wrong.
- Nothing binds on a negated form, and treating it as its own operator makes that obvious rather than arbitrary. Under `not (effect is Heal heal)` the illegality would look like a carve-out.
- `without` in a `for` clause is the structural form of the same test. Two contexts, one idea — cross-referenced so a third spelling does not appear.
- `!=` stays separate: it compares values, `is not` tests a label.

**Enums** (`#enums`)
- Explicit label values dropped <- schema pre-agreement (Runtime & Deployment, *Schema agreement is a premise*) means no number needs to be stable outside the language. Ordinals also keep entity-attached labels dense, so component ids stay `base + offset`.
- First label is the zero value <- everything else in the language zero-initializes to a valid value; an enum with an invalid state would be the exception. Consequence: declaration order is semantic, for the default and for label ordering both.
- Bare-name construction of a payload label (`effect = Heal`) is not an enum rule at all <- it follows from a type being constructible by name alone (`#construction`), which was generalized for this. Ranges must include zero (`#ranges`), so a zeroed payload is always a legal value.
- Whole-payload binding (`is Heal heal`) rather than positional destructuring (`is Heal(amount)`) <- `type name` is the language's own declaration shape, so no pattern sublanguage is introduced; adding a field to a label cannot silently rebind anything; and the payload is reached with `.` like every other field. Cost: `heal.amount` instead of `amount` for single-field payloads.
- Rejected alternative: one declared type per payload (Zig, Odin). Same dot access, but forces a `HealData` declaration for a single integer.
- Payload unreachable without a binding <- an enum value has no fields, so this needs no fallibility machinery. It also closes the three-inconsistent-spellings problem structurally rather than by convention.
- Enums and tagged unions stay one construct. Rust/Swift/ML combine, Zig/Odin/C# split, and the dividing line is whether the label's *number* is part of the concept. Test for revisiting: count the "if payload-free" carve-outs. Relational operators are the first (`Pending.md#data-modeling-and-declaration-syntax`, comparison pass). A second and third mean it is two constructs sharing a keyword.

**Signatures** (`#signatures`)
- The rule is *a procedure reference must be derivable from source, not from data* — not "procedures are not values". The value framing bans comparators and sorting, which are legitimate; the source-derivability framing bans exactly the storage cases.
- <- Static access-set extraction (`Engine Core.md#scheduling-and-execution`). A statically resolved reference propagates the callee's access set into the caller's exactly. A reference read from data makes the callee underivable; a conservative union over every proc ever assigned into the slot is decidable but pessimistic, and the pessimism is invisible at the call site — which `Design Principles.md#no-hidden-control-flow-no-implicit-costs` rules out.
- No anonymous proc literals <- with no literal there is no argument position to nest one call inside another's, so callback pyramids are unspellable rather than discouraged. Also keeps the call site naming intent (`by_weight`) instead of showing mechanism.
- Anonymous *listener* blocks are not a counterexample: top-level only, no capture, statically bound, cannot be registered or removed. An unnamed declaration, not a value.
- No stack-level binding of a signature parameter either. A local `let chosen = a if condition else b` stays source-derivable, but it is the point where propagation degrades from exact to a union and the call stops inlining to one direct callee. Dropped for simplicity; an `if` expresses the same thing.
- Separate `define signature` rather than Pascal-style inline (`proc before(Item a, Item b) returns boolean` in the parameter list) <- the inline form is legible but dense for a non-expert reader. Cost accepted: one extra declaration per signature.
- The word `signature`, not `delegate` <- C# delegates are storable in fields, multicast and rebindable at run time, all of which this refuses. Prior art with matching semantics has no keyword at all (Algol 60 formal procedures, standard Pascal procedural parameters, Rust `impl Fn`, C++ template comparators); every language with a *named declaration* for it (C#, Go) made it storable. Turbo Pascal adding procedure types is the exact point Pascal's became storable.
- PascalCase, not snake_case <- a signature sits in type position, and `sort(Item items[], item_comparison before)` reads as two parameter names in a row.

**Paren-less calls** (`#procedures`)
- Zero-or-one argument, statement position only <- a zero-argument paren-less call lets standard-library procedures read as keywords (`test_and_halt`), which shrinks the built-in language surface instead of growing it.
- A bare name in argument position is a reference, never a call <- otherwise `baz foo` means "runs foo" or "does not run foo" depending on the callee's parameter type, which is type-directed hidden control flow. Cost accepted: `print get_score` is an error, `print get_score()` is the spelling.
- Signatures not being a return type independently closes the same ambiguity, but the reference rule is the one that holds without it.

**Procedure overloading** (`#procedure-overloading`)
- Parameter names excluded <- a name is not part of the call's type information, so including it would let two indistinguishable call sites resolve differently.
- Constrained numerics resolve as their base type <- constraints refine representation, not identity (`Language Implementation.md#unified-representation`).
- Spec states least-coercion generally; the numeric ranking ("prefer the smaller scale change") lives in the implementation doc, because it is a consequence of the scaled-integer representation rather than a surface rule.
- A type and a proc cannot share a name <- identifiers being unique within their scope already forbids it; no separate namespace rule is needed. Reverse identifier uniqueness and `Health(current: 100)` becomes ambiguous between construction and call.
- -> Covers the plain "one name, many types" case on its own, so traits are needed only for generic code (`Pending.md#data-modeling-and-declaration-syntax`).
- Open: a hand-written concrete generic query taking precedence over the autogenerated one is a specialization rule, and must be squared with these when generics are designed.

**Statements and expressions** (`#statements-and-expressions`)
- Expressions never contain statements <- no lambdas or closures (`#procedures`). A lambda is the construct that would put a statement body in an expression position, so declining it is what makes the one-directional nesting total rather than incidental. Statements still nest by containment: block bodies are statement lists.
- A call is the only form that is both statement and expression <- `create`, `delete`, `match` and `fail`/`assert` are statement forms, and the value-producing form of `if` is the separate ternary spelling. So the rule only has to constrain calls; `a + b` and `e.Health` are excluded by not being statements at all, not by a purity test.
- The side-effect requirement <- inferred procedure purity (`Pending.md#systems-scheduling-and-parallelism`). The rule is stateable now and checkable once purity inference lands, which other work needs regardless.
- The previous iteration barred unbound construction on ownership grounds — the binding governs lifetime, so construction without a destination was invalid. Not carried: values are copied and own no memory. The general side-effect rule reaches the same cases and is preferred over a construction-specific one.
- Discarding with `_` is not an exception <- `_ = f()` is an assignment statement that contains the call, so a side-effect-free call is reachable through the ordinary statement forms.

---

## Runtime & Deployment

**Schema agreement is a premise, not a per-feature concern** (`Engine Core.md#frame-model-and-synchronization`)
- Peers pre-agree on every data schema — component ids, layouts, enum ordinals. Synchronization transfers raw bytes against that shared schema, so no wire-level identifier needs to be stable independently.
- -> Declaration-order ordinals are safe for enums. Explicit label values were dropped partly on this basis (`Language Spec.md#enums`); nothing outside the language assigns meaning to the number.
- For saved data the answer is to store the schema alongside the raw data and remap on load when it has changed, rather than to freeze identifiers at the language level. Version skew is handled once, in the save path, instead of constraining every declaration.
- Reverse the pre-agreement premise — a peer or save that can carry data written against an unknown schema — and stable identifiers become load-bearing everywhere.

**Console backend choice** (`#execution-backends`)
- Console portability is not blocked by Wasm as such; the constraint is JIT, forbidden by certification. AOT and interpretation both sidestep it while keeping one artifact.

---

## Design Principles

**Scripts are portable** (`#scripts-are-portable`)
- -> Makes the compile-time/load-time split tractable: if the only per-deployment variable is module presence, the load boundary can resolve everything.

---

## Deferred consistency

Doc edits already known to be owed, blocked on a decision. Clear an entry the moment its blocking decision lands.

**Systems as a listed ECS primitive** (`Design Principles.md#ecs-focused`)
- Blocked on: whether systems become a first-class construct (`Pending.md#systems-scheduling-and-parallelism`, importance 5).
- Owed edit: if systems land as a language construct, reword the principle to match what they actually are — an organization and scheduling construct, not a behaviour container. If they do not, strike `systems` from the primitive list.
- Accepted as a known inconsistency in the meantime (Joaquin, 2026-08-22). Do not "fix" it by quietly deleting the word; the decision comes first.

**"The language has arrays and nothing else"** (`Pending.md#data-modeling-and-declaration-syntax`, sets and maps)
- Owed edit: tuples now exist, so the opening line of that entry is stale. Left alone because the entry's argument is about containers under the flat-copyable rule, which tuples do not change — they are stack-only.

**`load` re-firing on hot reload** (`Runtime & Deployment.md#hot-reload`)
- Blocked on: reload semantics for live state (`Pending.md#compilation-and-backend`, importance 4).
- Owed edit: state whether `load` re-fires. File-level variables are Unmanaged and come back zero-initialized, so something must repopulate them; but re-firing duplicates the entities the first firing created.
