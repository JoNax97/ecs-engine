# ECS Scripting Language — Syntax Reference (Round 2)

Compiled from syntax-by-example discussion. Companion to the feature/non-feature list.

## Values & Declarations

```
x := 5                    // inferred
y : f32 = 2.5              // explicit type
```

## Structs & Construction

```
struct Vec3 {
    x: f32
    y: f32
    z: f32
}

v := Vec3{x: 1, y: 2, z: 3}     // construction always uses {}, never ()
d := Vec3{}                      // all-defaults construction — still needs {}

Vec3{x: 1, y: 2, z: 3}           // bare, unbound construction — compile error
```

`{}` is reserved for construction, `()` for calls — avoids ambiguity when a type and a proc share a name, and avoids collision with named-argument call syntax.

## Components & Lifetime Tiers

```
component Health {
    current: f32
    max: f32
}

h := Health{current: 100, max: 100}   // fresh, disconnected data (stack-backed)
h2 := h                                // ordinary copy — h2 stays disconnected too

h = set_component(my_entity, h)        // explicit promotion — h now live-backed
h.current -= 10                        // writes straight through to entity data
h2.current = 0                         // h2 unaffected — was copied before promotion
```

- Components are a single type — no separate "handle" type ever appears in the type system.
- The compiler transparently switches a component's backing storage (stack bytes vs. entity storage) based on what it can prove; the author only ever sees one consistent type and operation set.
- `:=` always copies, everywhere, no exceptions. Behavior differs only by *what* is being copied, never by a hidden type distinction.
- For-loop query bindings are always live-backed by construction (see Queries).

## Handles & Validity

```
r := request_resource(#player_model)

r.is_valid()                // generic check — true only when Ready

match r.state {
    Pending { }
    Ready   { spawn(r) }
    Failed  { retry() }
    Dead    { }
}
```

- Handle state is a small built-in enum (`Pending / Ready / Failed / Dead`), not a bool.
- `.is_valid()` is dot-sugar, true only for `Ready`.
- Handle state doubles as the language's result/fallibility mechanism — no separate `Result<T, E>` type exists. Multi-return is never used to smuggle in an error slot.

## Arrays, Fixed Strings, Symbols/Tags, Sized Generics

```
scores: f32[10]                     // fixed array — [] reserved purely for "N of this type"
label: FixedString<32>               // capacity is a compile-time parameter, lives in <>
names: FixedString<32>[10]           // array of 10 fixed strings, each capacity 32

queue: Queue<Enemy, 8>               // type param + size param, both in <>
queues: Queue<Enemy, 8>[4]           // array of 4 such queues

some_id := "some id"                 // inferred as String; identical literals may be compiler-interned, invisibly
log: String                          // dynamic, growable, handle-backed, NOT component-safe
```

- `<>` — any compile-time parameter baked into a type (type params and size params alike).
- `[]` — reserved strictly for array repetition ("N copies of this type").
- Two string types only: `String` (general-purpose, the literal-default type; identical literals may be compiler-interned as an invisible optimization — this never affects the type or serializability) and `FixedString<N>` (inline, fixed capacity, component-safe, trivially serializable — the only string type allowed in a component).
- `tag` is a separate, declared, module-namespaced construct, not a string type — used for first-class ECS presence marking:

```
module combat
tag stunned

add_tag(e, stunned)
remove_tag(e, stunned)

query cc(e: Entity, without stunned) { ... }              // unqualified, used within the declaring module
```

```
module other_module
import combat

query check(e: Entity, without combat:stunned) { ... }    // qualified from outside, `:` for type/tag-like access
```

- Tags require declaration (unlike a freeform interned literal) specifically because an undeclared, unnamespaced tag risks silent cross-module bit collisions — a real gameplay hazard, unlike an ordinary string-literal naming collision.

## Tagged Unions & Match

```
union Payload {
    Damage: f32
    Heal: f32
    Nothing
}

component Effect {
    payload: Payload
    duration: f32
}

match v in e.payload {
    Damage { h.current -= v }   // v narrowed to Damage's payload type per-arm
    Heal   { h.current += v }
    Nothing { }
}
```

- Unions allowed as struct/component **fields**, not as the component type itself (breaks filter/storage model — use multiple mutually-exclusive components instead).
- Storage: fixed max-variant-size layout.
- One bind name declared at the `match` header; compiler narrows its type per arm.

## Procedures

```
proc lerp(a: f32, b: f32, t: f32) -> f32 {
    return a + (b - a) * t
}

// multiple return values
proc divmod(a: i32, b: i32) -> (i32, i32) {
    return a / b, a % b
}
q, r := divmod(10, 3)

// dot-sugar on first parameter
effect.get_magnitude()   // sugar for get_magnitude(effect)

// procs as call-stack values — named procs only, no lambdas/closures
proc apply(pred: proc(Enemy) -> bool, e: Enemy) -> bool {
    return pred(e)
}
```

- Only free procedures — no first-class methods.
- Procs cannot be stored in components or persisted game-tier state; cannot be used as callbacks.

## Access Modifiers

```
proc apply_damage(h: Health, amount: f32) { ... }        // defaults to readwrite
proc log_health(h: readonly Health) { ... }                // opt-in self-restriction

proc on_config_loaded(cfg: readonly GameConfig) { ... }    // host-imposed, not author's choice
```

- One consistent rule everywhere (queries included): default `readwrite`, opt-in `readonly`.
- No mandatory annotation anywhere — tooling can flag "could be readonly" as an optimization hint instead.

## Queries & Systems

```
query apply_shield(h: Health, s: optional Shield) {
    if s.is_valid() {
        h.current += s.absorb
    }
}

query on_damaged(h: changed Health) {
    // guaranteed present — changed implies present, no validity check needed
}

query cleanup(p: Position, without Dead) {
    ...
}

query find_closer(e: entity, p: readonly Position) {
    ...
}
```

- `query` is a standalone declarative construct — not a manual for-loop. Engine resolves the filter and calls the body per matching entity.
- Presence-mode (`optional`/`changed`/`without`) before access-mode (`readonly`) when both apply.
- `without` never binds a name — pure structural requirement.
- Entity handle access is explicit: `e: entity`.
- Standalone queries (no owning system) can be invoked from anywhere via `run_query(...)` — used as helper building blocks inside plain procs.
- Nested `run_query` calls (query invoking another query) are disallowed — keeps the halt containment boundary meaningful.

```
system CombatSystem {
    query apply_shield(h: Health, s: optional Shield) { ... }
    query cleanup(p: Position, without Dead) { ... }

    proc tick() {
        run_query(apply_shield)
        if some_condition {
            run_query(cleanup)
        }
    }
}

system MovementSystem {
    query update_pos(p: Position, v: readonly Velocity) { ... }
    query apply_drag(v: Velocity) { ... }
    // no tick() — both queries auto-run, in declaration order, every frame
}
```

- `system` is always zero-arg — instantiated only by the engine, never constructible from script.
- A `tick()` proc gives full manual control (`run_query`, conditionals). Omitting `tick()` auto-runs all contained queries in declaration order.

## Modules

```
// file: my_module/health.script
module my_module

component Health { current: f32; max: f32 }
```

```
// file: my_module/movement.script
module my_module
import other_module
import optional combat_addon

query update_pos(p: Position, v: readonly Velocity) { ... }

if combat_addon {
    proc thing(bonus: f32) { ... }
} else {
    proc thing() { ... }
}
```

- Every file declares `module name` at the top — no wrapping braces at file scope, all files sharing the name are merged into one module.
- `import name` — mandatory dependency, no presence check possible or needed.
- `import optional name` — may be absent; presence check (`if name { }`) required; tooling flags unguarded use.
- `if name { }` on a module import: dead-branch-eliminated — at compile time for compiled mods, after load for interpreted mods. Same syntax either way.
- Top-level conditional declarations (`if module { proc foo(){} } else { proc foo(){} }`) behave like preprocessor `#ifdef` — exactly one branch survives, no signature-matching required between branches, compiler only validates what's left.
- No per-script import friction beyond this — no separate manifest-level import syntax needed.
- Local bundling of shared source (no module registration) always produces a distinct, private type per bundler — by design, not a bug. Sharing a real type across modules requires a proper `module` dependency.

## Generics & Traits

```
component TimedEffect<T> {
    value: T
    duration: f32
    elapsed: f32
}

query tick_effect<T>(e: TimedEffect<T>) {
    e.elapsed += delta_time()
}

// hand-written concrete version takes precedence over autogenerated
query tick_effect(e: TimedEffect<Damage>) {
    ...
}

trait Magnitude {
    magnitude: i32
}

component Health {
    magnitude: i32
}
trait Magnitude for Health { }                    // naive — names/types already match

component Damage {
    amount: i32
}
trait Magnitude for Damage {
    magnitude = amount                             // field alias
}

trait Magnitude for i32 {
    magnitude = get_magnitude, set_magnitude        // proc-backed (getter, setter)
}

proc do_something<T: Magnitude>(m: T) {
    m.magnitude += 1        // works identically regardless of backing form
}
```

- Generics resolved via monomorphization — `<T>`, plain, no bracket/marker needed (types are never values in this language, so no ambiguity exists to guard against).
- Traits declare **fields only**, never procs directly. A field can be satisfied by: a same-named/typed field (naive, empty `trait X for Y {}` body), a differently-named field (alias), or a getter/setter pair (proc-backed) — all inside one `trait X for Y { }` block, one entry per field.
- Trait conformance is always explicit (`trait X for Y { }`), never structural/duck-typed — applies to types the author doesn't own too (primitives included).
- No access modifiers on trait fields — read/write is a system's decision at the point of use, never dictated by the trait (core ECS philosophy: data doesn't define usage).

## Error Handling

```
halt("bad index")     // explicit — script relinquishes execution for this entry point

// implicit halts — out-of-bounds, div-by-zero, exceeded execution cap — no syntax needed
```

- `halt` (not "panic") — communicates that only the current entry point's execution stops; the engine regains control and continues elsewhere.
- Unwinds to the nearest engine-called entry point: tick fn → whole tick aborts; query callback → only that entity's iteration aborts, rest continue; cursor resume → only that resume aborts.
- Expected "might not exist" situations (dead handles, unloaded resources, absent optional components) are never halts — always handled via handle-state checks instead.
- Bounded execution (infinite loop/recursion protection): a simple runtime cap → halt. No proof-of-termination requirement, no annotations.

## Deferred to Later Sessions

- Exact call/API shape for `get_component`/`set_component`/`request_resource` (syntax patterns shown here are illustrative, not final)
- Relations syntax
- I/O surface beyond the async-handle resource pattern
- Testing hooks
- Struct/primitive declaration order (`struct Name {}` vs Odin-style `Name :: struct {}`) — unresolved, low-stakes
