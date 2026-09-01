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
- -> `record` nesting costs nothing at run time, which is what makes records a free abstraction rather than a structural choice.
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
- -> Going *wider* than 64 bits is shelved rather than queued (`Shelved.md#data-modeling-and-declaration-syntax`, Joaquin, 2026-08-31). Ruling if the need appears: a separate type, never a wider default, so the cost stays visible and nothing existing changes width. The two open sub-questions live there.
- Round-to-nearest on rescale <- truncation's error is directional, accumulating linearly rather than cancelling. Toward-zero is also the most expensive of the three modes in fixed point, since an arithmetic shift floors and negatives need a sign-dependent bias.

**Division** (`#division`)
- The split is by intent, not by operand type. At `f = 0`, `/` was covering two operations that never coincide: an exact integer partition (index, bucket, count, wrap) and an inexact ratio. Only the second has a precision question, so no rounding policy could reconcile them — one of them is not rounding anything. Splitting by type instead is what made the same expression change meaning when a field's declared type changed.
- `//` floors rather than truncates, against the C-family expectation the audience actually holds. Full argument in `faq-material.md#why-does--floor`; the short form is that floor and truncation agree on every non-negative use (counts, indices, ticks) and disagree only on spatial arithmetic, where truncation is a bug. The choice is invisible where it is free and correct where it is visible.
- `//` is a primitive, not sugar for `floor(a / b)` <- the `f = 17` intermediate cannot distinguish an exact division result from one a hair below it, so the compound form is off by one at exactly the grid boundaries. Peculiar to fixed point; Python has no such gap because its integer division is exact.
- `%` takes the divisor's sign because the identity `a == (a // b) * b + a % b` links it to `//`. Not an independent choice. Rejected: a second pair (`rem`/`rem_euclid` style) — `/` has no remainder to pair with, since a fractional division result is exact, so only one whole division exists to take one.
- `/` targets a fixed `f = 17` rather than deriving one from the operands. Rejected: `max(fa, fb)`, which is the SQL `DECIMAL` family's rule and inherits its hole — two whole operands give `f = 0`, so `1 / 3` is `0`. SQL patches this with an arbitrary significant-digit floor and the engines disagree on the constant.
- Also rejected: deriving the scale from the destination (Ada's `universal_fixed`, `BigDecimal.divide` refusing without an explicit scale). Correct in spirit, but a chained expression like `(a / b) * c` has to push the required scale backwards through the tree, and the multiply rule `fa + fb` admits many splits that land on the same destination. A fixed `f = 17` reaches the same observable answer with no inference, and reuses the constant `#inferred-bindings` already fixed.
- -> The precedent worth remembering: every fixed-point system with a genuine choice refuses to infer a scale for the division result. Only SQL picks, and its rule is the one regarded as a wart.
- Precision degradation is decided at compile time and is silent. Runtime detection was rejected twice over: it costs a check and a data-dependent shift on every unproven operation, and the build-independence it was defended on (`Engine Core.md#frame-model-and-synchronization` — a build-dependent arithmetic result desyncs peers) comes free once the shift is baked into the artifact.
- Silent rather than warned <- numeric refinement is optional (`Language Spec.md#numeric-types`), and a warning whose remedy is "add a `range`" converts an optional annotation into one written to quiet the compiler. Floating point loses precision continuously without complaint; the difference here is that the amount lost is a compile-time fact, so tooling can show it on request (`Design Principles.md#show-the-machinery-in-motion`).
- Unrefined code is provable anyway <- storage defaults are intervals. Undeclared `integer` is signed 32-bit, undeclared `decimal` is 32-bit at `f = 13`, so `range` tightens an interval that already exists. The unprovable residual is values genuinely unbounded by their storage, not values merely unannotated.
- Store-time range checking cannot substitute for the pre-shift check: an overflowed intermediate can land back inside the destination's range, so the store never sees it.

**No infinity or NaN** (`Language Spec.md#arithmetic`)
- Not a design choice so much as an absence of anywhere to put them: a scaled integer reserves no bit patterns, where IEEE 754 spends an exponent value on them. The alternative to halting is a silently wrong number, not a placeholder.
- Worth stating explicitly despite reading as obvious <- integer division by zero errors in every language, but *float* division by zero does not, and the audience arrives from float-based engines where `x / 0` yields `Infinity` and the frame continues. The departure is from their daily experience, not from a language rule.
- -> Comparison is total, which the equality pass can rely on: no `NaN != NaN` case to special-case in sorting, deduplication or cached comparisons.
- -> A silently wrong value is worse here than a halt, since state is bulk-synchronized and a wrong number desyncs peers rather than reporting itself.

---

## Language Spec

**Explicit declaration** (`#variables`)
- <- Closes the pit-of-failure where a misspelled name silently declared a new binding.
- `let` carries no annotations <- it means "representation does not matter", which is only honest where the generous representation is free. That is true of a stack slot and false of storage.
- -> `let` is banned at the top level. Same premise: file state is laid-out storage, so the generosity has no basis there. Reverse the premise and the ban goes with it.
- File-level variables are declared like fields, but bare variable-size data is dynamically backed rather than annotated, because `dynamic` opts a *field* out of inline storage and there is no enclosing layout at file scope.

**Changing precision** (`#changing-precision`)
- The line is the declared type keyword, not lossiness. Precision narrowing within `decimal` is lossy too and stays implicit; what earns explicitness is crossing to `integer`, because that is what an author reads at the use site.
- No cast syntax at all <- a cast-shaped spelling imports C's truncation semantics, and neither of this language's conversions truncates: the implicit rescale rounds to nearest and `//` floors. Three behaviours in play, so the operation is named rather than defaulted.
- -> Forces `precision(0)` to be unspellable, or the same representation would follow two conversion rules depending on which keyword declared it (`Shelved.md#data-modeling-and-declaration-syntax`).
- Making all narrowing explicit was rejected: storing a wide expression into a declared field is how ordinary arithmetic terminates, so requiring a wrapper there makes routine code unwriteable.

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
- Cost: nested calls read inside-out. The pipe syntax that was the designated answer is now shelved too (`Shelved.md#data-modeling-and-declaration-syntax`, Joaquin, 2026-08-31), so that cost has no live answer by choice. `.` keeps its single meaning either way; if the pressure returns, the pipe form is the one to reopen, not dot-sugar.
- -> `then` is unclaimed, and `Pending.md#errors-and-control-flow` (alternative ternary) now wants it for `if cond then a else b`.

**Non-goals section** (`Language Spec.md#non-goals`)
- Purpose is calibration, not justification: a reader arriving from C# or Rust learns the shape of the language before the syntax. It is not a rationale list — the *why* stays in `Shelved.md` and here.
- Entry condition: only **settled** absences. `null`, exception propagation and threading are excluded because their entries are still open in `Pending.md`; listing them would state a decision that has not been made.
- "No asynchronous execution" is admissible despite the async mechanism being undesigned, because the synchronous property is settled independently of which mechanism is chosen (`Pending.md#storage-and-memory-layout`, asynchronous operations).
- Not the home for small feature absences (unary `++`, operator overloading, dot-calls, macros). Those are lookup answers, already inline where they matter, and would turn the section into a dumping ground.
- Load-bearing negatives do **not** live here. A rule a checker enforces goes where it bites, as part of the positive rule it constrains — otherwise it reads as trivia and gets missed.

**Tuples** (`Language Spec.md#tuples`)
- Stack-only <- a storable tuple would need a position under the flat-copyable rule, and would then be a `record` without a name. Keeping them off `define`d types removes the storage, schema and taint questions outright rather than answering them.
- No annotations on elements <- annotations attach to declarations and a tuple literal is not one. Consistent with `let` taking none (`#variables`). This is also a second reason a tuple cannot be a component field: a `string` or array inside a `define`d type must state its storage (`#storage`) and a tuple has nowhere to state it.
- Cap of four <- makes ordinal accessors complete: `first` through `fourth` cover the whole space, so unnamed tuples never need `.0` and `[]` keeps its single meaning (`#basic-syntax`). Past four the better option is a `record`, which costs one line. Reverse the cap and positional access has to come back.
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

**`record`, not `value`** (`Language Spec.md#records`)
- Renamed because `value` was carrying three jobs: the keyword, the assignment-semantics category (which covers numerics, strings, tuples and enums too, so the keyword was a strict subset of it), and the ordinary sense of "what an expression produces". Only the first was nameable, so it moved.
- `record` <- Pascal, Ada, F# and Elm all use it for a named-field aggregate with copy semantics, which is exactly the construct, and it is SQL vocabulary, already a stated inspiration (`Language Spec.md#scope`). Plain English, so it does not cost `Design Principles.md#readable-by-non-engineers` the way `struct` would.
- Known misread: C#'s `record` is a reference type. Half self-correcting, since C# records compare by value and Loom's do too — only the copy-versus-reference half misleads.
- Rejected `data` (components and enums are data too, so it distinguishes nothing) and renaming the *category* to copied/shared (works as adjectives, but "handle" is still needed as a noun for the reference itself — lifetime, validity state and identity equality are all statements about a handle, and an adjective cannot carry them).
- The category keeps the word `value`, which is now unambiguous.

**Values and handles** (`Language Spec.md#data-modeling`)
- Two behaviours, not three. Entities, components and future resources are all handles; everything else is a value. Reference semantics for handles are meant to read as classes do in a managed language, with the runtime owning the memory instead of a general arena.
- Supersedes the provenance-inferred backing idea (previous iteration). That version made the destination of a write a fact about where an identifier came from; carrying it in the type makes it a fact about the type, which is what `Design Principles.md#no-hidden-costs` asks for.
- Validity is structural, not checked, for entity and component handles: neither can be stored in a component or file state, nor held across a frame boundary, so it can never refer to data that is gone. Same shape as the signature rule — the reference exists only where it cannot be saved. This is a property of those two kinds and not of handle-ness; a resource handle is long-lived and needs a checked story instead (`Pending.md#data-modeling-and-declaration-syntax`). The spec currently states neither.
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

**Match arms** (`#conditional-statements`)
- An arm is a comparison with the subject as its implied left operand, so `<=`, `in` and label tests are one grammar rather than a pattern sublanguage. Same move as `when Heal heal` reusing `type name` instead of destructuring.
- A bare operand implies the operator too, resolving to whichever equality the operand's type takes — `==` for a value, `is` for a label. Not a carve-out for enums: it reuses the `==`/`is` split the language already draws (`#operators`), so `when 5` and `when Stun` are one rule. Binding still falls out, since `is` is the only operator that binds.
- Right operand must be constant <- C# and Rust both require it and push expressions into a separate guard. Constant arms over enum labels stay dispatchable (jump table, per-label bitmap); arbitrary expressions would make `match` exact sugar for an `if`/`else if` chain and give the construct nothing of its own.
- No exhaustiveness requirement, order is semantic, overlap is legal. Consistent with there being no compiler-known totality anywhere else in the language, and it keeps the first-match rule readable rather than making arm order a diagnostic.
- Cost: an enum `match` that misses a label is silent. Tooling territory (`Design Principles.md#show-the-machinery-in-motion`), not a language rule.

**`in` takes any collection-like operand** (`#membership-semantics`)
- Reverses the earlier "range and nothing else" rule, which rested on cost: `x in range(0..10)` is two comparisons and `x in array` is a linear scan, and the two were held to be the same three characters with unrelated cost. That framing was wrong about the operand — the collection is named at the site in both, so the cost follows a declared type and is not hidden. `Design Principles.md#give-visibility-into-performance-and-costs` already puts cost surfacing in tooling rather than in source, so a lint covers what the rule was protecting.
- The surviving reason is symmetry: `for x in collection` and `if x in collection` are one operand shape in two positions. That is a property of the language, where the cost argument was a property of one operand pair.
- Precedent reconsidered. Odin restricts `in` to O(1) operands, but Odin has maps *and* bit sets — two collections that look alike and cost differently, which is the Python `list`/`set` trap. Loom accepts that trap knowingly: the collection is named at the site either way, so a second spelling buys a cost signal the reader can already read off the operand, and costs a snag. Smoothness over cleanliness, per the recorded precedence (`Design Principles.md#clean-clear-smooth`).
- Operand order was considered and rejected — `collection contains x` does not make cost more visible, since both forms name the operand. It also collides with `has` (component presence), needs a new reserved word, and has no loop-position form, so ranges would keep `in` while collections took `contains`.
- Strings are the one operand the symmetry does not justify: `in` on a string is subsequence containment, not element membership, and there is no `char` to iterate to. Kept anyway, following Python, which documents the same two relations under one operator. Strings become iterable once slices exist (`Pending.md#data-modeling-and-declaration-syntax`), which closes the gap rather than widening it.
- Literal ranges only for now; ranges are values, so a named range follows once value constants are settled (`Pending.md#data-modeling-and-declaration-syntax`).

**Comparison and equality pass** (`#comparison-semantics`)
- `==` is exempt from the cost rule for the same reason `in` is: cost follows the operand's declared type, and `string body dynamic` announced itself at its declaration. There is no cheap twin it can be confused with.
- Components compare structurally though they are handles <- handle-ness governs aliasing on write, not equality. Usefulness decides it: component comparison is across entities in the majority of cases. Identity equality would make `a.Health == b.Health` false for any two distinct entities, which is a silently wrong answer to the thing people actually write.
- Entities compare whole, generation included <- an entity is opaque and has no fields, so identity is the only thing there is to compare. The rule is *equal handle value means the same element*, which is what forces canonical encoding onto the storage pass (`Pending.md#entity-identity-and-generation`).
- Arrays check element type statically and length at run time. Bounds are part of the type for checking but not for comparability, since a bounded array compared against a dynamic one has no static length. This depends on bounds being capacity rather than count (`Pending.md#data-modeling-and-declaration-syntax`).
- Relational stays numeric-only, plus `ordered` enums. String ordering was dropped — cost stopped being an argument once `==` was exempt, so the remaining question was semantics, and byte order reads as alphabetical and is not.

**`ordered` enums** (`#enums`)
- The trichotomy break it fixes: label order gave `<`, structural equality gave `==`, so two values with one label and different payloads made `a < b`, `a == b` and `a > b` all false, and any sort or clamp got an inconsistent comparator.
- Lexicographic label-then-payload is what Rust, Haskell and Swift all do. What they have that Loom lacks is *opt-in* — `derive(Ord)`, `deriving Ord`, declaring `Comparable` — so a type whose payload is not orderable simply never gets ordering, and no language rule about payloads is needed. Annotations are Loom's equivalent surface; what is missing is only trait resolution, and "every field is orderable" is one recursive compiler check rather than a constraint system.
- Chosen over restricting relational operators to payload-free enums, which would have been the first "if payload-free" carve-out — the tripwire this file already names for whether enums and tagged unions should have stayed one construct. An `ordered` annotation is a capability request that payload-free enums trivially satisfy, so the tripwire does not fire.
- Also chosen over inference: under inference, adding a payload field silently removes `<` from every use site, and the error lands away from the edit that caused it. Under the annotation, it errors on the declaration line the author just changed.
- Rejected: exposing the ordinal as `.order` and ordering only that. Clean — `==` stays uniform everywhere and relational stays numeric-only with no carve-out at all — but it taxes the majority use case (severity, tiers, weekdays) with noise, and it re-exposes the label's number as a value, which explicit label values were dropped to avoid. Once it is an integer, `order + 1` and storing it in a component are spellable, and reordering labels stops being a free refactor.
- Extending `ordered` past enums was dropped from `Pending.md` as a standalone entry (Joaquin, 2026-08-31); what survived moved into the traits entry, since the live question is not "should records be orderable" but *how a capability is authored*. Joaquin's direction: the annotation is a request the compiler checks by finding a procedure of the right shape (`Compare(T a, T b) returns integer`), which reuses `signature` rather than adding conformance machinery. Cuts against traits being fields-only and conformance being explicit — recorded there as the thing to settle.
- No label-only comparison of two runtime values. `is` covers the named case; sorting and grouping by kind fall out of label-first ordering. The gap is deduplication by kind, which has no confirmed use case — accepted as a hole rather than queued, and moved to `Shelved.md#data-modeling-and-declaration-syntax` (Joaquin, 2026-08-31). Precedent set by that move: a gap with no intent to close belongs in Shelved with a revisit condition, not in Pending; a new "known issue" type was considered and declined, since it would differ from `pending` only by invisible intent.

**Negated presence and narrowing** (`#operators`)
- Single operators, not `not` applied to a result. That is what keeps them from being a second spelling of an existing composition — the objection that shelved dot-sugar.
- `has no` and `has not` are both accepted, for the same operator, because English needs both: `has no` before a noun (`has no Shield`), `has not` before a past participle (`has not Moved`). Tags are frequently participles — `Moved`, `Dead`, `Stunned` — so neither form covers every operand. This is the one place two spellings were accepted deliberately, and it is grammar rather than preference.
- `no` is reserved. Casing is advisory, so a component could legally be named `no`, which would make `e has no` ambiguous. `not` was already reserved as the boolean operator.
- <- Precedent is direct rather than analogical: SQL `IS NOT NULL` / `NOT IN` and Python `is not` / `not in`, and SQL is a stated inspiration.
- -> Removes a precedence question. `not target has Shield` needs `has` to bind tighter than `not`; `target has not Shield` has nothing to get wrong.
- Nothing binds on a negated form, and treating it as its own operator makes that obvious rather than arbitrary. Under `not (effect is Heal heal)` the illegality would look like a carve-out.
- `without` in a `for` clause is the structural form of the same test. Two contexts, one idea. The split is principled and should be stated as such: a preposition modifies a binding in a declarative clause, a verb forms a boolean expression — `if e with Health health` is not a sentence.
- A third spelling had appeared and was corrected: the query example in `Language Spec.md#queries` read `not target has Shield`, against the idiom rule in `#operators` (Joaquin, 2026-08-31). Open, and deliberately left open: whether `not <expr> has <T>` is *illegal* or merely non-idiomatic. Leaving it legal costs a third spelling that examples will drift back toward; banning it is a rule about where `not` may apply, which nothing else in the language needs.
- `!=` stays separate: it compares values, `is not` tests a label.

**Enums** (`#enums`)
- Explicit label values dropped <- schema pre-agreement (Runtime & Deployment, *Schema agreement is a premise*) means no number needs to be stable outside the language. Ordinals also keep entity-attached labels dense, so component ids stay `base + offset`.
- First label is the zero value <- everything else in the language zero-initializes to a valid value; an enum with an invalid state would be the exception. Consequence: declaration order is semantic, for the default and for label ordering both.
- Bare-name construction of a payload label (`effect = Heal`) is not an enum rule at all <- it follows from a type being constructible by name alone (`#construction`), which was generalized for this. Ranges must include zero (`#ranges`), so a zeroed payload is always a legal value.
- Whole-payload binding (`is Heal heal`) rather than positional destructuring (`is Heal(amount)`) <- `type name` is the language's own declaration shape, so no pattern sublanguage is introduced; adding a field to a label cannot silently rebind anything; and the payload is reached with `.` like every other field. Cost: `heal.amount` instead of `amount` for single-field payloads.
- Rejected alternative: one declared type per payload (Zig, Odin). Same dot access, but forces a `HealData` declaration for a single integer.
- Payload unreachable without a binding <- an enum value has no fields, so this needs no fallibility machinery. It also closes the three-inconsistent-spellings problem structurally rather than by convention.
- Enums and tagged unions stay one construct. Rust/Swift/ML combine, Zig/Odin/C# split, and the dividing line is whether the label's *number* is part of the concept. Test for revisiting: count the "if payload-free" carve-outs. Relational operators nearly became the first and did not — `ordered` made it a capability request instead. There are currently none; two or three mean it is two constructs sharing a keyword.

**Signatures** (`#signatures`)
- The rule is *a procedure reference must be derivable from source, not from data* — not "procedures are not values". The value framing bans comparators and sorting, which are legitimate; the source-derivability framing bans exactly the storage cases.
- <- Static access-set extraction (`Engine Core.md#scheduling-and-execution`). A statically resolved reference propagates the callee's access set into the caller's exactly. A reference read from data makes the callee underivable; a conservative union over every proc ever assigned into the slot is decidable but pessimistic, and the pessimism is invisible at the call site — which `Design Principles.md#no-hidden-costs` rules out.
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
- No marker on the reference form — no sigil, no keyword (Joaquin, 2026-08-31). Every language needing no marker (Python, JS, Go, Rust, C# method groups) shares one property, a call always takes `()`, which makes bare-name-as-reference the intuition the reader arrives with. The languages that *did* mark it — Pascal `@Foo`, VB `AddressOf Foo`, Ruby `method(:foo)` — are exactly those that kept general paren-less calls, so the marker is the price of the call rule, not a fix for it. Cheaper lever: narrow where a paren-less call is legal (`Pending.md#data-modeling-and-declaration-syntax`, commands). The residual ambiguity needs a zero-argument proc passed where both a signature type and its return type fit, which is rare enough to reject outright if it arises.
- Removing the paren-less rule costs less than it looks: the language's voice comes from keywords (`create ... with`, `delete`, `fail`, `on`, `for`/`where`/`do`), none of which are procedure calls, so the rule's only real beneficiary is `print`. Compressed out of `Pending.md#data-modeling-and-declaration-syntax` (commands) — needed if that entry is reopened, not to pick it up.
- Python 2 is not prior art despite the `print "x"` resemblance: `print` was a reserved grammar production, not a paren-less call, so the ambiguity never arose and the cost surfaced as a capability hole (`f = print` unwriteable). PEP 3105 removed the special case for that reason.

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

**Query clauses are the primary form, not an alternative one** (`#queries`)
- C# is the cautionary case, not the model. Its query syntax is vestigial because method chaining is always available, composes further, and reads like the rest of the language — so the declarative form is a dialect a reader must opt into, and most do not.
- The condition that makes it primary here is the absence of the competitor: no closures (`#procedures`) means no `.Where(x => ...)` chain is constructible, and no dot-call sugar (`Shelved.md#data-modeling-and-declaration-syntax`) means no chain to hang it on. The clause form is not the better of two spellings; it is the only one.
- -> The two shelvings are load-bearing for this, not merely aesthetic. Reverse either and the clause form acquires the competitor that made C#'s vestigial.
- The cost direction is also inverted from C#'s, and that is the argument to make to an arriving reader. LINQ's lambdas are why it allocates closures and enumerators; a clause body is syntax rather than a value, so predicates capture nothing and the declarative form is the *fast* one. Declarative-and-cheap is a claim C# cannot make.
- -> Clause vocabulary can grow on cost grounds without the ergonomic escape hatch existing. That is what makes the reductions worth reopening (`Pending.md#queries-and-predicates`) and what makes the admission rule — fixed-size result free, variable-size result must show its buffer — the whole of the gate.

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

**Clean, clear, smooth** (`#clean-clear-smooth`)
- Descriptive, not aspirational. Added because each pairwise conflict already had a decided instance in the docs: clean-vs-clear settled by bare-name-as-reference (`Language Spec.md#procedures`), clean-vs-smooth by `has no`/`has not` being one operator with two spellings (`#operators`), smooth-vs-clear still open in the three `where`-shaped constructs (`Pending.md#data-modeling-and-declaration-syntax`). The frame was extracted from those rulings rather than imposed on them.
- A frame over the existing principles, not three more entries <- the list is already long, and appending would make the three read as peers of the commitments they generate. Sorting: clarity covers `#no-hidden-costs` and `#data-layout-follows-declared-intent`; cleanliness covers `#minimize-language-breadth-and-feature-creep`; smoothness covers `#readable-by-non-engineers`.
- The precedence is the load-bearing part. Three qualities without an order justify any decision, since every proposal is strong on at least one. Clear-then-smooth-then-clean is read off the record above, not chosen: clarity has not lost a ruling, and cleanliness lost the one time it was tested against smoothness.
- Explicitly not brevity <- the goal was mis-stated as terseness during design discussion, which conflicts with static strictness. It resolves once the axis is friction rather than length: strictness lands at declaration sites, which are written once and read often, so the verbosity is spent where it amortizes. Same shape as SQL's verbose DDL against readable DML.
- Loom's strictness generates little notation because the parts of Rust that produce dense syntax — lifetimes, borrows, generics, `?`, closures — are all non-goals. Prior art for strict-and-low-symbol is Ada and Pascal; Go is the evidence that density arrives with generics specifically, which is where this frame will next be tested (`Pending.md#data-modeling-and-declaration-syntax`, generics).

**Reasoning compressed out of Pending** (recovery notes, 2026-08-31)
- Intrinsic fallibility, cost analysis: range arithmetic becomes load-bearing type checking rather than metadata — interval propagation through the operators, decidable at the load boundary, and it must be **specified**, since an unrecognized-but-equivalent range expression degrading to fallible is the same cost cliff as the `where` predicate-shape problem. Runtime cost is a branch the author wrote, no unwinding machinery.
- Query as a form inside a proc, the cost check that could have killed it: access-set extraction survives because a query stays syntactically visible and nothing callable is stored in data — which holds only because `#signatures` and the absence of closures already paid for it. Event attachment loses nothing since `on tick some_proc` exists; the `for`/`where` region is unchanged and its edges become visible.
- Erased component handles, why extraction stays sound: a narrowing arm is a branch, and extraction already unions across branches, so sets over-approximate — false conflicts, never missed ones.
- Gating on a global condition, why the singleton candidate was rejected: it relies on unstated optimizer behaviour, the same trap as recognized-versus-unrecognized predicate shapes in `Pending.md#queries-and-predicates`.
- Reductions: the pulled spec text is no longer quoted verbatim in Pending. Full wording is in git history; the entry keeps the reducer example and the cost split.
- Intrinsic fallibility against Verse (`Pending.md#errors-and-control-flow`): Verse forces a guard on every division because it knows nothing about the divisor. Declared ranges are what make the same feature affordable here, and the ergonomics invert — a required guard means the domain was under-specified, so the remedy is to state the range, which is `Design Principles.md#domain-over-technicism` exactly. Runtime cost is a branch the author wrote, no unwinding machinery, which suits both the AOT and interpreter targets.
- Conformance by proc shape (`Pending.md#data-modeling-and-declaration-syntax`): the prior-art split is Go structural against Rust/Swift explicit `impl`, with C# and C++ operator resolution as shape-scanning precedent. The standing argument against structural is that a shape match can be accidental.

**Linearity is load-bearing, not incidental** (`Language Spec.md#non-goals`, no asynchronous execution)
- The non-goal is usually read as being about frames and awaiting. It is broader: a body runs to completion and nothing resumes it, so any construct with a resume point is a suspension regardless of how it is spelled.
- -> Killed capture-free deferred execution on its own, where the cost argument could not reach it (`Shelved.md#events-and-change-detection`). With nothing captured the cost is one compile-time-sized flag per site — cheap, and still rejected. Worth remembering as the case where linearity did the work alone (Joaquin, 2026-08-31).
- Same shape as the coroutine ruling and the single-use-listener ruling; three constructs, one objection.

**Compose constructs, not values** (`#compose-constructs-not-values`)
- The syntactic/value split is the whole content. Without it the principle contradicts two standing rulings — no closures (`Language Spec.md#non-goals`) and `#no-general-indexing-or-materialization` are both refusals of composability, and both are correct. Syntactic composition resolves at compile time and costs nothing; value composition materializes intermediates. Same word, opposite cost.
- Sits directly above `#no-general-indexing-or-materialization` in the document so the second reads as the bound on the first.
- Kind against annotation is stated as identity, not as a checklist. An earlier draft used "an invariant the runtime maintains, or a matching primitive queries can use" — struck, because that was `relationship` described twice and would not have generalized. It also failed its own stress test: `define component Target targets(8) mutual` is spellable, so a can-this-be-annotated test rejects relationship, which is the wrong answer.
- Worked cases behind the wording: `integer` against `decimal` are two kinds because an integer is not a decimal with no fractional part — the language already had to make `precision(0)` unspellable (`#changing-precision`), which is the same fact surfacing as a hole. `tag` is a kind because it alters how data is stored and reached, not because it has no fields. `relationship` is a kind because it is a concept expressible as a component pair, an entity or a pivot table — a kind names what a thing is, not how it is stored. `range`/`precision` are annotations because behaviour is unchanged and any procedure taking a number still takes it. `ordered` is an annotation because it only adds an operation set.
- Two mechanical tells, both read off those cases. An annotation the overload resolver cannot see is safely an annotation (`#procedure-overloading`: constrained numerics resolve as their base type). An annotation that constrains what may *contain* the declaration is not one — `dynamic` is the only one that does, since a record holding a dynamic field cannot sit inside a component (`Language Spec.md#storage`).
- -> `dynamic` is the open counterexample, and it resolves into `Pending.md#storage-and-memory-layout` (addressability of a dynamic component field) rather than standing on its own. Under copy semantics it is a storage statement like `length(32)` and the container restriction is a layout consequence; under sharing, a write through one identifier is visible through another and it is a kind wearing an annotation. Settling copy-against-share settles this.
- -> `query` fails on identity: a query and a proc are the same thing to the runtime — code that runs — so the kind names no distinct thing (`Pending.md#queries-and-predicates`). Pre-empts the same question for systems and commands; the ordering argument is that queries are the checkable instance and systems is the `5`-rated one, so the precedent is set on the cheap case first.
- First application of the principle to a *construct* rather than a kind: bulk entity creation (`Language Spec.md#creation`) fails the brevity reading — a shorter spelling for a loop — and passes on being a different operation to the engine, one N-slot allocation against N independent ones. The distinction to reuse: "does the engine do something else", not "is it shorter to write".
- Bulk creation specifics, since the spec states the rule without them (Joaquin, 2026-08-31): runtime count, shared `with` list, per-entity variation deliberately dropped rather than deferred. The result lands on the existing dynamically-backed array form (`Language Spec.md#arrays`), so it needed no new rule and was not blocked on arrays-as-capacity after all — that blocker only applied to a compile-time-bounded result. Value it protects: under inverted-bitmap storage, memory cost tracks entity-ID clustering (`Pending.md#storage-and-memory-layout`), and this is the only construct that can guarantee contiguous IDs.
- The cost being guarded against is multiplication, not vocabulary size: every kind adds a row to every rule stated about kinds — visibility, storage, comparison semantics, query interaction, serialization. Kept out of the principles doc, which states intent rather than accounting.
- Distinct from `#minimize-language-breadth-and-feature-creep`, which declines features outright. This one accepts the capability and rejects the *separate construct* for it. Breadth minimization says no; this says yes, but built out of what exists.

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
