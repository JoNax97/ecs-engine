## Purpose

Items considered and deliberately not adopted, kept so the reasoning is not re-derived. Section structure mirrors [Pending](Pending.md); an item moves here when it is decided against, and moves back only if the argument that killed it stops holding.

Each entry records what was proposed, why it was rejected, and what would have to change for the ruling to be revisited.

---

## Data Modeling and Declaration Syntax

### Dot-sugar on the first parameter

`effect.get_magnitude()` for `get_magnitude(effect)`. Not adopted: it is a second spelling of a call that already has one, and it invites attaching behaviour to data instead of manipulating data.

Dropping it keeps `.` meaning exactly one thing — reaching into data — and removes the need for a lookup rule between component types and procedures on an entity, which would have made the advisory casing convention load-bearing.

The cost is that nested calls read inside-out. `let` bindings name the intermediates instead.

### Pipe syntax

A left-to-right spelling for nested calls, so `clamp(get_magnitude(effect), 0, 1)` reads in application order. Leading candidate was a `then` keyword piping into the first parameter, with every step written as a call whose first argument is missing:

```
let m = effect then get_magnitude() then clamp(0, 1)
```

Purely syntactic — it would desugar to the same nested calls, with no runtime cost and no effect on overload resolution or access-set extraction. The empty parentheses were load-bearing: they keep a step a call, so the rule that a bare name in argument position is a reference needs no exception. `|>` was rejected on spelling, since `|` is the comment character.

Not adopted, and now decided by principle rather than by taste: it is a second spelling for a construct that already has one, which [Compose constructs, not values](Design%20Principles.md#compose-constructs-not-values) declines. It differs from dot-sugar above in not implying that data owns behaviour, but that only clears one objection, not the main one.

The costs recorded against it, worth keeping because they apply to any future variant: the call site stops showing real arity, since `get_magnitude()` reads as zero-argument but is one and `clamp(0, 1)` reads as two but is three — Elixir pays the same cost. Piping only into the first parameter constrains library design, since a procedure must be written subject-first to be pipeable. And a chain mixing pure transformations with mutating steps reads as one flowing transformation while half of it is a side effect, which would have forced steps to be restricted to side-effect-free procedures and made this depend on [inferred procedure purity](Pending.md#systems-scheduling-and-parallelism).

Prior art splits on where the piped value lands: Elixir, F# and OCaml insert it as the first argument by convention; Clojure has two operators for first and last; Hack and R use an explicit placeholder token, stating the position at the call site rather than relying on convention.

Revisit if inside-out reading of nested calls becomes a measured pain rather than an anticipated one — ECS bodies mutate fields more than they transform values, so the pipeline case may simply be rare here. Note that shelving this leaves that cost with no live answer, which is deliberate. `then` is consequently free, and the [alternative ternary syntax](Pending.md#errors-and-control-flow) entry now wants it.

### Surface unification of `integer` and `decimal`

`integer` is the `f = 0` case of the same representation ([unified representation](Language%20Implementation.md#unified-representation)), so the surface could follow the implementation and collapse to one numeric type — `integer` as sugar for a zero-precision `decimal`.

Not adopted. The unification is worth having internally, where it removes the integer case from scale reconciliation, width inference and overload ranking. On the surface it would buy one type instead of two and cost the only narrowing that is currently visible: assigning a fractional value into a whole-number field would become an ordinary rescale and round silently, in the one place an author most needs to state which rounding they meant. [Changing precision](Language%20Spec.md#changing-precision) makes that conversion explicit instead, which requires the two types to stay distinct.

`precision(0)` is unspellable for the same reason — it would be a `decimal` indistinguishable from an `integer` in representation while following a different conversion rule.

Revisit only if the explicit-conversion rule is dropped. Division does not bear on it either way: `/` and `//` split by intent rather than by operand type.

### Numbers wider than 64 bits

Raising the 64-bit ceiling — a higher `precision(n)` cap, or wider storage widths — so that larger magnitudes or finer fractions become expressible.

Not adopted, and not a current need. The ceiling is load-bearing rather than arbitrary: `f = 17` exists because a product's `fa + fb` intermediate must fit 64 bits, `let` generosity is affordable only because 64-bit is the widest thing there is, and [precision selection](Language%20Implementation.md#precision-selection) picks its constant shifts against it. Raising it changes the cost of all arithmetic to buy something almost no code needs, and costs the single-artifact property besides, since wasm3 implements neither i128 nor SIMD.

The ruling if the need ever appears: a **separate type**, not a wider default. That makes the cost visible where it is paid and can be added without touching anything that exists, where lifting the cap would change every stored width and every intermediate.

Two things that would have to be settled at that point, recorded so they are not re-derived:

- It is an exception to [Numeric Types](Language%20Spec.md#numeric-types), which states that width and precision come from annotations rather than from separate types. The exception is defensible on the grounds that this is a different operation set — native instructions against synthesized multi-instruction sequences with a per-backend cost — rather than merely a wider storage width, but it has to be argued rather than assumed.
- "Bigger" is two needs. Enormous magnitude with little precision (idle-game currency, lifetime statistics) wants a floating exponent; more fractional bits than `precision(5)` wants a wider fixed-point type. One type serving both would serve neither well.

Revisit when the ceiling actually binds in real code — not before, since the shape of the answer depends on which of the two needs shows up first.

### Comparing the labels of two runtime enum values

`is` tests a label but requires a literal on the right, so "do `a` and `b` carry the same label, whatever it is" has no spelling.

Not adopted, and recorded as an accepted hole rather than a rejected proposal — no spelling was designed, because the need has not appeared. Most of what the operation would serve is already covered: sorting and grouping by kind fall out of [`ordered`](Language%20Spec.md#enums) comparing the label first, and the named case is `is` itself. What is left is deduplicating by kind.

Revisit if a confirmed deduplicate-by-kind case appears, which in practice means effects or similar enums being held in a list — undesigned, and the thing to watch for.

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

The capture-free degenerate case — "run this once, later", with nothing captured, for deferring expensive cleanup past the current point — is rejected too, and on different grounds (Joaquin, 2026-08-31). Capture was never the objection to it: with nothing captured, what persists is one compile-time-sized flag per deferral site, no allocation and no runtime table, so the cost argument above does not reach it. It is rejected because execution is linear. A body runs to completion and nothing resumes it, which is what [no asynchronous execution](Language%20Spec.md#non-goals) states; a deferral point is a suspension wearing different syntax. Where the work belongs to an entity, the marker-plus-query form above already covers it.

---

## Compilation and Backend

### Load-time codegen

Folding load-time-known values into native code during the Wasm-to-native step at load, rather than emitting indirection for them. Would make any load-time-resolved constant free at run time instead of costing a lookup. Not needed while the only load-time fact is module presence, since a presence check is a branch rather than a value feeding computation. Becomes relevant the moment a load-time value participates in layout.

### Load-time checking of dependency versions

Allowing a manifest to admit a *range* of versions per dependency, with guards (`module.version >= 2`) selecting between implementations. The rule that makes it sound: unguarded code type-checks against the range's **floor**, and guards narrow only *upward*. Writes check against the floor, reads against the ceiling, so both stay statically decidable without enumerating configurations. Deferred because a single declared version per dependency removes the problem entirely, and version skew is a mod-ecosystem concern that will be designed better against real modules than in the abstract.

### Virtualized data layouts

Scripts addressing fields through a layout table populated at load, rather than baking static offsets. Would let a type's size or field widths vary per deployment while keeping one portable artifact. Rejected for now on the honest-costing bar: it puts an indirection on every field access to buy configuration flexibility that [Scripts are portable](Design%20Principles.md#scripts-are-portable) says the engine should be absorbing instead.

Related and dropped outright rather than deferred: **two-tier compilation** (mods compiled once and portably, internal modules compiled per target). It resolves the same tension, but by giving up the single-artifact guarantee, and it splits the backend into two paths where the less-tested one is the one shipped to third parties.
