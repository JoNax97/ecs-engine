## Purpose

This document specifies **how** the featured and guarantees in the [language spec](Language%20Spec.md) are delivered. Everything here is mechanism: it may change freely, provided the contract in the language spec continues to hold. Scripts must never depend on anything stated only in this document.

The division: *which* operations are cheap is contract, *how* they are made cheap is mechanism.

Unwritten areas are listed at the bottom.

---

## Numeric Representation

Numbers are fixed-point. The language exposes only `integer` and `decimal`; width, signedness and fractional precision are derived from the declared `range` and `precision` annotations.

Numbers are byte aligned (rounded up to multiples of 8). Max storage efficiency is sacrificed for direct addressability.

### Integers

Signedness is taken from whether the declared range admits negative values. Width is the smallest supported storage size that holds the full range. An undeclared range defaults to signed 32-bit.

Representation is never biased. A range is sized from `max(|min|, |max|)` and stored directly, rather than offset into an unsigned span — storing `range(-10..100)` as `v + 10` would make logical zero sit at bitwise 10, which breaks zero-initialization and puts a correction on every operation. Keeping the two zeros identical is what lets creation stay a memset.

### Decimals

`precision(n)` is declared in decimal places. The implementation selects the smallest **power-of-two fractional width** that represents `n` decimal places — that is, the smallest `f` where `2^f >= 10^n` — so that scaling between stored and logical values is a bit shift rather than a division. Total width is the fractional width plus the bits needed for the declared integer range, plus one for sign where the range admits negatives.

For example: `precision(5)` needs `2^f >= 100000`, giving `f = 17`; a range of `-8000..8000` needs 13 bits and a sign bit; `17 + 13 + 1 = 31, rounded up to 32`.

These widths are a language-level contract; the resulting widths must stay as documented in the language spec.

### Unified representation

Internally there is one numeric representation: a scaled integer with a fractional width `f`. `integer` is the `f = 0` case of the same form, not a separate kind of value. The two surface keywords differ only in their defaults — `integer` defaults to `f = 0`, `decimal` to `f = 13`.

This removes a special case rather than adding one. Mixed-precision arithmetic already needs a scale-reconciliation rule (`precision(2)` plus `precision(5)`); folding integers in makes `integer` combined with `decimal` an instance of that rule instead of a separate conversion path. Overload resolution generalizes the same way: "prefer the non-converted overload" is "prefer the smaller scale change". Width and signedness inference collapses to one algorithm over `(range, f)`.

The unification is strictly internal. `integer` and `decimal` remain distinct types at the surface, since overload resolution and the author's declared intent both depend on the difference.

Division needs care but not a second code path. `integer / integer` at `f = 0` truncates; decimal division pre-shifts by `f`. One operation parameterized by a compile-time constant.

### Computation

These rules above apply to in-memory storage. For computations, the naive approach is to expand all numbers to the max width (eg, 64-bit). A possible optimization is to generate variants of math primitives and procs based on the actual sizes used. This is TBD and is excluisively a performance improvement. The naive method must be correct by itself.

---

## Enum Payloads

An enum label may carry a payload, so an enum is laid out at the size of its largest variant plus its label discriminant. The size is therefore fixed and known at declaration, which is what keeps enums usable as component fields under the flat-copyable rule.

---

## Pipeline

Two terms, deliberately distinguished:

- **Front end** — parse, validate, resolve. Kept execution-strategy-agnostic: it makes no assumption about what the result will be executed by, and could in principle feed a backend other than Wasm.
- **Compiler** — the whole pipeline, from source through to emitting a Wasm bytecode object. "Compiler" implies the commitment to a target that the front end deliberately avoids.

Stages:

```
source
  -> parse            (front end)
  -> name resolution  (front end)
  -> type check       (front end)  <- runs over every branch, including dead ones
  -> constant propagation
  -> load-time elimination         <- strips resolved-false branches
  -> codegen
  -> Wasm object (one per module)
```

### Load-time elimination

Two separate things, and only the first is a contract.

**Full checking is guaranteed.** Every branch is name-resolved and type-checked, including ones that resolve false. This forces a **two-pass** process rather than a single skip-if-false walk: check everything first, strip afterwards. The cheaper single-pass approach would let code behind a disabled optional import rot undetected, which the spec forbids.

**Elimination is an optimization.** The spec does not promise that a resolved-false branch emits nothing — evaluating the condition at run time is equally correct. For elimination to apply below file scope, constant propagation has to run before or alongside it rather than only at top level, since conditionals are legal inside procedure bodies and query `do` blocks.

> Because elimination is not a guarantee, an author has no language-level assurance that a branch behind an absent module costs nothing. That gap wants a tooling answer — surfacing what was stripped — rather than a spec one. Tracked in [Language Pending](Language%20Pending.md).

### Load-time constant taint

The spec bars a constant assigned from a load-time conditional from determining a layout. The front end therefore carries a taint bit on constant bindings — set when the initializer reads module presence, propagated through any constant derived from it — and checks it wherever a value feeds an array bound, range constraint, or enum value.

This is the same mechanism as the flat-copyable taint sketched in [Language Pending](Language%20Pending.md), and should share an implementation with it.

### Incremental compilation

Each file compiles to its own Wasm object independently. Hot-reload swaps a single module's object into the running instance without a whole-program rebuild.

This requires cross-module symbol linkage that stays stable while one module is recompiled and its dependents are not — the linkage cannot depend on layout decisions that shift when an unrelated module changes.

## Query Evaluation

### Structural matching

Conditions the spec describes as a "fixed presence check" are serviced by component presence bitmaps: components, tags, etc. all reduce to mask tests over the storage tables rather than per-entity work.

### Value predicates

`for` and `where` together form a single declarative region. The compiler may reorder conditions across the boundary between them freely; the split is an authoring convention only.

Within that region, predicates of recognized shape may be serviced by acceleration structures rather than evaluated per entity — for example, a `distance(...)` comparison answered from a spatial partition.

> The set of recognized predicate shapes is not yet specified. Until it is, two logically equivalent predicates may differ by orders of magnitude with nothing in the source distinguishing them. Tracked in [Language Pending](Language%20Pending.md).

Imperative blocks (query `do`s and procs) are more opaque to this analysis. A predicate hoisted out of `where` into a `do` body is subject to limited acceleration.In cases where a known primitive is used it might still be accelerated, but to a lesser degree and with less guarantees. 


### Reductions

`count` and cardinality reductions are answered from archetype population counts and relationship counters already maintained by the storage layer, requiring no scan. 

`sum`, `avg`, `max_by` and `min_by` visit every matching entity. There might be a possibility to proactively accelerate them (for example by keeping a running avg updated on component change) but that's at the compiler discretion and may not be relied upon.

Queries and procs with empty bodies are eliminated at compile time.


### Codegen notes

Enum structural matching implies **monomorphization**, not just an index. Because enum labels are a small closed set — the same property that makes a per-label bitmap affordable — the compiler can specialize per label rather than testing a label at runtime.

One mechanism, applied at two points:

- **Declarative.** A query filtering an enum field against a compile-time-resolvable set emits a specialized body per possible label.
- **Imperative.** A `match` against an enum component inside a query `do` can be rewritten as multiple specialized queries, each matching one label structurally — lifting a runtime branch back into the structural layer where it costs nothing.

Relationship equality compiles to a lookup through the backlink structure already maintained for mutual-relationship consistency. No new infrastructure: it reuses the bookkeeping that keeps both sides in agreement.

### Debug identifiers

Anonymous queries and procs get compiler-synthesized identifiers for profilers and debuggers — module plus line, or module plus matched component set. "Anonymous" means unaddressable from script, never invisible in tooling.

---

## Not Yet Written

Mechanism for the following is undecided. Each is a contract already stated in the language spec, or an engine behaviour the spec depends on:

- Chunk layout, and how ownership and `non_serialized` partition storage.
- The synchronization path itself: chunk selection, delta or whole-chunk transmission, peer topology.
- Whether `changed` fires on state arriving from a remote peer, and at what cost.
- Recognized predicate shapes and their acceleration structures.
- Storage for pointer-like component data (chunk-managed buffers).
- Wasm compilation and the host boundary, including hot-reload.
