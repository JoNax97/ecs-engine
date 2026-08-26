## Purpose

This document specifies **how** the features and guarantees in the [language spec](Language%20Spec.md) are delivered. Everything here is mechanism: it may change freely, provided the contract in the language spec continues to hold. Scripts must never depend on anything stated only in this document.

The division: *which* operations are cheap is contract, *how* they are made cheap is mechanism.

Unwritten areas are listed at the bottom.

---

## Numeric Representation

Numbers are fixed-point. The language exposes only `integer` and `decimal`; width, signedness and fractional precision are derived from the declared `range` and `precision` annotations.

Numbers are byte aligned (rounded up to multiples of 8). Max storage efficiency is sacrificed for direct addressability.

Representation is never biased. A range is sized from `max(|min|, |max|)` and stored directly, rather than offset into an unsigned span, so logical zero and bitwise zero are the same value.

### Integers

Signedness is taken from whether the declared range admits negative values. Width is the smallest supported storage size that holds the full range. An undeclared range defaults to signed 32-bit.

### Decimals

`precision(n)` is declared in decimal places. The implementation selects the smallest **fractional width** that represents `n` decimal places — that is, the smallest `f` where `2^f >= 10^n` — so that scaling between stored and logical values is a bit shift rather than a division. Total width is the fractional width plus the bits needed for the declared integer range, plus one for sign where the range admits negatives.

For example: `precision(5)` needs `2^f >= 100000`, giving `f = 17`; a range of `-8000..8000` needs 13 bits and a sign bit; `17 + 13 + 1 = 31, rounded up to 32`.

These widths are a language-level contract; the resulting widths must stay as documented in the language spec.

### Unified representation

Internally there is one numeric representation: a scaled integer with a fractional width `f`. `integer` is the `f = 0` case of the same form, not a separate kind of value. The two surface keywords differ only in their defaults — `integer` defaults to `f = 0`, `decimal` to `f = 13`.

Consequences:

- Mixed-precision arithmetic and `integer`-with-`decimal` arithmetic are the same scale-reconciliation rule, not separate conversion paths.
- Overload resolution ranks candidates by "prefer the smaller scale change".
- Width and signedness inference is one algorithm over `(range, f)`.
- Division is one operation parameterized by a compile-time constant: `integer / integer` at `f = 0` truncates; decimal division pre-shifts by `f`.

The unification is strictly internal. `integer` and `decimal` remain distinct types at the surface.

### Computation

The rules above apply to in-memory storage. Computation expands operands to the maximum width (64-bit). Narrower computation paths are a performance question only, tracked in [Pending](Pending.md#compilation-and-backend).

Rescaling a value to a narrower fractional width rounds to nearest, ties toward positive infinity: `(v + (1 << (f - 1))) >> f`. Truncation is not used — its error is directional, so it accumulates linearly through a chain of operations instead of cancelling.

### Inferred bindings

A `let` binding takes the most generous representation of its inferred surface type: 64-bit, with `f = 0` for `integer` and `f = 17` for `decimal`. Because `precision(n)` caps at `n = 5`, `f = 17` is the widest fractional width any declaration can name, so a `let` binding holds any value read from a declared field without narrowing.

Products set that cap. A multiply produces a `2f` intermediate before rescaling, and Wasm has no widening 64×64 multiply, so the intermediate must fit in 64 bits: `f = 17` leaves 29 bits of integer part. Raising `f` costs that headroom twice over.

---

## Parameter Passing

Parameters are always passed by reference. A value parameter is copied only if the body writes into it.

The copy is decided at compile time, not checked at run time: a [binding](Language%20Spec.md#bindings) cannot be reassigned, and the language has no reference parameters or closures, so writing into the parameter's fields is the only way to modify it. In this case, a copy is automatically generated on entry.

For values smaller than a reference, the compiler can choose to always pass it by value if that's more performant.

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

**Full checking is guaranteed.** Every branch is name-resolved and type-checked, including ones that resolve false. Checking is therefore **two-pass**: check everything first, strip afterwards.

**Elimination is an optimization.** A resolved-false branch is not promised to emit nothing. For elimination to apply below file scope, constant propagation runs before or alongside it rather than only at top level.

### Load-time constant taint

The spec bars a constant assigned from a load-time conditional from determining a layout. The front end therefore carries a taint bit on constant bindings — set when the initializer reads module presence, propagated through any constant derived from it — and checks it wherever a value feeds an array bound, range constraint, or enum value.

### Flat-copyable taint

[The flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) disqualifies any component holding a `dynamic` field below its top level. Eligibility is decided the same way: a `dynamic` field taints the `value` containing it, and the taint propagates outward to whatever holds that `value`.

The offending field path is stored alongside the taint at declaration time, so reporting a failure does not require re-walking the type.

### Incremental compilation

Each file compiles to its own Wasm object independently. Hot-reload swaps a single module's object into the running instance without a whole-program rebuild.

Cross-module symbol linkage stays stable while one module is recompiled and its dependents are not: linkage does not depend on layout decisions that shift when an unrelated module changes.

## Query Evaluation

### Structural matching

Conditions the spec describes as a "fixed presence check" are serviced by component presence bitmaps: components, tags, etc. all reduce to mask tests over the storage tables rather than per-entity work.

### Value predicates

`for` and `where` together form a single declarative region. The compiler may reorder conditions across the boundary between them freely; the split is an authoring convention only.

Within that region, predicates of recognized shape may be serviced by acceleration structures rather than evaluated per entity — for example, a `distance(...)` comparison answered from a spatial partition.

A predicate hoisted out of `where` into a `do` body gets limited acceleration at best: imperative blocks are opaque to this analysis, and only recognized primitives inside them are candidates.

### Reductions

`count` and cardinality reductions are answered from population counts and relationship counters already maintained by the storage layer, requiring no scan.

`sum`, `avg`, `max_by` and `min_by` visit every matching entity. Proactive acceleration is at the compiler's discretion and may not be relied upon.

Queries and procs with empty bodies are eliminated at compile time.


### Codegen notes

Enum structural matching implies **monomorphization**, not just an index. Enum labels are a small closed set, so the compiler specializes per label rather than testing a label at runtime.

One mechanism, applied at two points:

- **Declarative.** A query filtering an enum field against a compile-time-resolvable set emits a specialized body per possible label.
- **Imperative.** A `match` against an enum component inside a query `do` can be rewritten as multiple specialized queries, each matching one label structurally — lifting a runtime branch back into the structural layer where it costs nothing.

Relationship equality compiles to a lookup through the backlink structure already maintained for mutual-relationship consistency.

### Debug identifiers

Anonymous queries and procs get compiler-synthesized identifiers for profilers and debuggers — module plus line, or module plus matched component set. "Anonymous" means unaddressable from script, never invisible in tooling.

---

## Not Yet Written

Mechanism for the following is undecided.

- Recognized predicate shapes and their acceleration structures — [Pending](Pending.md#queries-and-predicates).
- Wasm compilation and the host boundary, including hot-reload — [Pending](Pending.md#compilation-and-backend).
- Layout consequences of ownership and `non_serialized` — [Pending](Pending.md#storage-and-memory-layout).
- `changed` on a non-owning peer — [Pending](Pending.md#events-and-change-detection).
