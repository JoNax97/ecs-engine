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
- Advisory, not compiler-enforced. Casing does not prevent collisions; what does is that a proc may not take a type's name (`Pending.md#data-modeling-and-declaration-syntax`, procedure overloading).

**ASCII identifiers** (`#identifiers`)
- <- Cost avoidance, not semantics. Unicode identifiers require NFC normalization and confusability handling — otherwise `é` as one codepoint and `e` plus a combining accent are different names that render identically, and Latin `a` and Cyrillic `а` are indistinguishable on screen. That is machinery bought to fix a problem that declining Unicode does not have.
- Does *not* rest on the casing convention. A caseless script (CJK, Arabic, Hebrew) cannot express the PascalCase/snake_case split, but since casing is advisory that argument only ever reached style, never validity.

---

## Runtime & Deployment

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

**Bound names versus the bare-`=` rule** (`Language Spec.md#variables`)
- Blocked on: whether parameters, query bindings and loop variables can be reassigned (`Pending.md#data-modeling-and-declaration-syntax`, importance 3).
- Owed edit: a sentence next to the reassignment rule covering bound names. As written, "a bare `=` reassigns a previously declared variable" reads as permitting `count = 0` on a parameter, because a bound name is in scope.
- Whatever lands must draw the line at the name, not the data: `target.Health.current += damage` stays legal in every version.

**`load` re-firing on hot reload** (`Runtime & Deployment.md#hot-reload`)
- Blocked on: reload semantics for live state (`Pending.md#compilation-and-backend`, importance 4).
- Owed edit: state whether `load` re-fires. File-level variables are Unmanaged and come back zero-initialized, so something must repopulate them; but re-firing duplicates the entities the first firing created.
