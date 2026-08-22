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
