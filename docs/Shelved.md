## Purpose

Items considered and deliberately not adopted, kept so the reasoning is not re-derived. Section structure mirrors [Pending](Pending.md); an item moves here when it is decided against, and moves back only if the argument that killed it stops holding.

Each entry records what was proposed, why it was rejected, and what would have to change for the ruling to be revisited.

---

## Data Modeling and Declaration Syntax

### Dot-sugar on the first parameter

`effect.get_magnitude()` for `get_magnitude(effect)`. Not adopted: it is a second spelling of a call that already has one, and it invites attaching behaviour to data instead of manipulating data.

Dropping it keeps `.` meaning exactly one thing — reaching into data — and removes the need for a lookup rule between component types and procedures on an entity, which would have made the advisory casing convention load-bearing.

The cost is that nested calls read inside-out. `let` bindings name the intermediates instead. If a pipeline style does become common, the answer is a [threading construct](Pending.md#data-modeling-and-declaration-syntax) rather than dot-sugar, so that `.` keeps meaning data.

### Surface unification of `integer` and `decimal`

`integer` is the `f = 0` case of the same representation ([unified representation](Language%20Implementation.md#unified-representation)), so the surface could follow the implementation and collapse to one numeric type — `integer` as sugar for a zero-precision `decimal`.

Not adopted. The unification is worth having internally, where it removes the integer case from scale reconciliation, width inference and overload ranking. On the surface it would buy one type instead of two and cost the only narrowing that is currently visible: assigning a fractional value into a whole-number field would become an ordinary rescale and round silently, in the one place an author most needs to state which rounding they meant. [Changing precision](Language%20Spec.md#changing-precision) makes that conversion explicit instead, which requires the two types to stay distinct.

`precision(0)` is unspellable for the same reason — it would be a `decimal` indistinguishable from an `integer` in representation while following a different conversion rule.

Revisit only if the explicit-conversion rule is dropped. Division does not bear on it either way: `/` and `//` split by intent rather than by operand type.

---

## Queries and Predicates

### GroupBy

Ruled out of the query language, but worth recording why the ruling might not hold. The objection that killed it was that materialized results reopen the heap-in-component hazard — and that objection does not apply if the result is scoped to frame-tier memory: bump-allocated, discarded at frame end, never touching a component. A transient, non-addressable GroupBy is therefore technically safe. It was rejected on the honest-costing bar instead — it did not clearly earn its cost — which is a design-taste call, not an architectural blocker. Revisit if a real use case appears.

---

## Events and Change Detection

### Single-use dynamic listeners

Proposed form: `on <event> do once ... end`, written inside a proc or query body, registering a listener that fires at most once. The motivating case is a second-order effect expressed next to its cause — marking an entity and stating the reaction to a later event in the same place, rather than in a distant query.

Rejected because a registration capturing an enclosing binding is a closure, and its environment has to survive the call frame. That makes it game-tier state that is neither fixed-size nor pointer-free, so it fails [the flat-copyable rule](Engine%20Core.md#the-flat-copyable-rule) and cannot be synchronized — peers would then disagree on second-order effects, which is the networking awareness [Transparent networking](Design%20Principles.md#transparent-networking-and-serialization) removes. It also requires a runtime subscriber list, against [Resolve at compile/load time](Design%20Principles.md#resolve-at-compileload-time), and leaves pending callbacks pointing into a module that [hot reload](Pending.md#compilation-and-backend) may swap. Same shape as the argument that ruled out coroutines.

What it was reaching for is already expressible: adding a marker component *is* the subscription, and a static query over that marker *is* the handler. That form is data rather than code, so it copies, syncs, survives reload, and is idempotent by construction — the component is present or absent, never registered twice. Removing the marker is the `once`.

Worth revisiting only in the restricted form where capture is limited to a single entity binding. The captured environment is then exactly a marker component, and the construct becomes a static transform rather than a runtime registration. Open even then: what the generated component is called, whether it is author-visible, and whether the saved locality is worth a construct at all.

---

## Compilation and Backend

### Load-time codegen

Folding load-time-known values into native code during the Wasm-to-native step at load, rather than emitting indirection for them. Would make any load-time-resolved constant free at run time instead of costing a lookup. Not needed while the only load-time fact is module presence, since a presence check is a branch rather than a value feeding computation. Becomes relevant the moment a load-time value participates in layout.

### Load-time checking of dependency versions

Allowing a manifest to admit a *range* of versions per dependency, with guards (`module.version >= 2`) selecting between implementations. The rule that makes it sound: unguarded code type-checks against the range's **floor**, and guards narrow only *upward*. Writes check against the floor, reads against the ceiling, so both stay statically decidable without enumerating configurations. Deferred because a single declared version per dependency removes the problem entirely, and version skew is a mod-ecosystem concern that will be designed better against real modules than in the abstract.

### Virtualized data layouts

Scripts addressing fields through a layout table populated at load, rather than baking static offsets. Would let a type's size or field widths vary per deployment while keeping one portable artifact. Rejected for now on the honest-costing bar: it puts an indirection on every field access to buy configuration flexibility that [Scripts are portable](Design%20Principles.md#scripts-are-portable) says the engine should be absorbing instead.

Related and dropped outright rather than deferred: **two-tier compilation** (mods compiled once and portably, internal modules compiled per target). It resolves the same tension, but by giving up the single-artifact guarantee, and it splits the backend into two paths where the less-tested one is the one shipped to third parties.
