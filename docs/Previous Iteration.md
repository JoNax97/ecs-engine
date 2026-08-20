## ECS-Constrained Scripting Language - Outdated iteration

Objective

A Domain-oriented scripting layer for an ECS game engine: 

The language should abstract away technical considerations wherever possible, letting the user think in gameplay terms rather than implementation mechanics. This applies broadly (queries, relations, serialization), not just memory: lifetime tiers are one instance of it — they map onto decisions gameplay scripters already make (frame/entity/game scope), not feel like exposed memory management

Additional characteristics
- Safe/sandboxed — no way to construct invalid memory access
- No manual memory management — no free()/dealloc from script
- No GC overhead — no tracing collector, no pause

Target: Odin as host language. Feasibility assessed as capable of a full game, not just mods/small scripts — constraints limit how data is held, not what logic is expressible.

## Core Principle

Scripts never own memory directly. All data is either:

- Stack-local values (primitives, structs) — zero-init on declare, copied on assign, freed at scope exit automatically.
- Handles to runtime-owned data — acquired only via host API calls, never constructed (new doesn't exist).

## Lifetime Tiers
Tier	| Backing |	Notes
Call stack |	true stack |	scoped to method call
Frame |	bump/linear allocator |	reset at frame boundary
Entity |	via components |	tied to ECS entity lifecycle
Game |owned by systems, or global |	lives until explicitly released / process exit

Containment rule: never store a shorter-lived handle into a longer-lived slot. Checked at compile/write-time (structural), since it depends only on declared types, not runtime state.

Struct tier inference: a struct's tier = the most restrictive (shortest) tier among its fields, computed recursively at type-definition time. Mixed-tier fields within a struct are allowed; the struct as a whole just inherits the shortest one. Error messages use a precomputed field-path (e.g. x.a.b.c) stored alongside the tier, so no re-walk is needed on failure.

Crossing tiers (e.g. stack struct → entity component) goes through explicit copy APIs (set_component), never implicit aliasing.

## Two Handle Categories

Both needed — they solve different problems:

Generational handles (index + generation) — for entity/component references. Destruction is a domain event (entity destroyed, component removed), independent of who's referencing it. Cheap: no cost on copy.

Reference-counted handles — for script-owned values (host collections, other owning handles) at game tier only. Destruction has no independent trigger — last reference dropping is the signal. Bump/decrement on every copy (including across tiers, since auto-release makes early-reassignment of the source a real hazard, not just a directional one).

Frame/stack-tier handles never need refcounting — their scope boundary is static and known at compile time.

## Structural Changes / Destruction
- Entity destruction and component removal are treated as the same operation (destroy = remove all components + return ID to pool).
- All structural removal deferred to end-of-frame, not just destroy. This makes every handle obtained and used within the same frame valid with zero runtime checks — the whole class of "handle invalidated mid-frame" hazards disappears by construction.
- Generational checks are only needed once: on first dereference of a handle that crosses into a new frame (i.e., was persisted at game-tier and read back later). Not per-access.
- Bitset tracks removed/pending-destroy components; queries filter these out by default (cheaper than requiring every system to check "is this alive").
- On-destroy cleanup systems run during the flush pass, before data is actually freed.

## Storage Architecture

Considered two options:

- Archetype/table storage (e.g. flecs) — real hazard: adding a component to entity A can trigger swap-remove relocation of an unrelated entity B in the same table, invalidating any handle held to B mid-frame. Not solved just by deferring removal — adds can relocate too.
 
- Inverted hierarchical bitmap storage (StaticEcs, C#) — each component owns a presence bitmap over fixed entity slots; entities never move in memory. This eliminates the cross-entity relocation hazard entirely (not just mitigates it). Memory cost is not inherently higher — empty bitmap blocks don't materialize storage; actual cost depends on entity-ID clustering, not the architecture itself. Same-entity-removal hazard still needs the frame-deferral rule above.

Since Odin has no existing port of either lib, and a Wasm-script boundary requires the ECS core to directly own the memory scripts read (no double-marshaling through a C library), ECS core will need to be implemented natively in Odin regardless of which architecture is chosen.


## Queries

Declarative, not script-driven loops — script declares a filter (with/without/optional/readonly-readwrite), runtime resolves and iterates, calling into script per entity/block. Keeps scripts stateless in the hot path.
Query objects declared once (system-level, game-tier), resolved once, reused every frame — not re-resolved per call.
Structural filters — plain bitwise AND over presence bitmaps.
Change filters (added/changed this frame) — same cost model, via a dirty bitmap/version-per-block alongside presence, reset at frame boundary. Cheap, first-class.
Value filters (e.g. health < 50) — not expressible as bitmap ops; same cost as an if in the iteration body either way. Worth exposing as syntax sugar for ergonomics, not as a performance feature — don't build indexing infra unless profiling justifies it for a specific hot filter.
Read/write access declared explicitly per query (also needed for parallel system scheduling — conflict detection requires declared, not inferred, access sets).


## Amortization / Update Rates

True coroutines (suspend mid-iteration, resume next frame) are disallowed — that's holding call-stack state across a frame boundary, violating the tier rules.
Resumable cursor pattern instead: position/accumulator stored as game-tier system state; each resume starts a fresh call-stack scope. Good for budgeted "process N per frame" work.
Different update rates (e.g. distant entities every other frame): simpler as bucketing — partition query by entity_id % K, process one bucket per frame. No suspension mechanism needed.

## Construction Syntax (no new)
- Struct literals (Vec3{x:1, y:2, z:3}) — pure stack values, no allocation, tier = the struct type's inferred tier.
- Host-managed types use the same literal syntax, dispatched differently by the compiler based on type: list{Enemy, 100} compiles to a host factory call returning a (refcounted, if game-tier) handle. One syntax, two backends, decided by the type declaration — author doesn't need different syntax to express which one they mean.
- A bare literal-construction with nothing binding it (no assignment) is a compile error — the binding governs lifetime/ownership, so construction without a destination is invalid, not a silent leak-preventer.
- Reassignment of a game-tier owning handle auto-releases the old value (refcount decrement) — chosen over requiring an explicit reset().
- Arrays with compile-time-known size need no new — declare with static size; runtime-variable size pushes into the collection/multi-component pattern instead.

## Guest-Side Optimizations (opaque to script author)
- Common library internals (e.g. collection APIs) can maintain raw pointer caches on the guest (Wasm) side to avoid per-element host boundary crossings — but this must live entirely inside compiler-emitted/trusted standard library code, never exposed as an authorable capability, or it reopens the aliasing hazard the handle system exists to prevent.
- Safety mechanism: pair the cache with a cheap version stamp (host bumps a counter on any invalidating op; guest checks it once per scope, not per access) — same generational-check idea applied to memory regions instead of entities. Cost is per-scope, not per-access, so it doesn't erode the perf win.


## Language/Runtime Implementation Strategy
- Custom front-end is unavoidable — readonly/readwrite syntax, query/relation sugar, tier enforcement are language-level features; no existing embeddable scripting language (Lua, Wren, AngelScript, etc.) has these as native concepts, only as APIs bolted on top.
- Execution backend is a real choice, separable from front-end design:
  - Forking an existing VM (e.g. Wren) — faster to bootstrap, but inherits a GC-based object model that has to be fought/ripped out, and means maintaining a permanent fork.
  - Wasm — favored given Odin as host (no CLR, so IL is off the table). Sandboxing (linear memory, no ambient authority) is structural, not policy enforced by your own compiler. Odin/Wasm interop via mature runtimes (wasmtime/wasmer) is straightforward. Own only the compiler backend; runtime improvements come from upstream.
  - Console portability is not blocked by Wasm specifically — the actual constraint is JIT (forbidden on most consoles for cert/security), solved via AOT-compiling Wasm to native ahead of time (e.g. via Cranelift) or falling back to a pure interpreter (wasm3/wasmi) — same script binary either way, execution strategy chosen per platform.
   
##  Performance Goal
AOT (not JIT) compilation; minimize boundary crossings rather than per-call overhead (batch/iterate inside one call, not per-entity crossings); static typing, no boxing/dynamic dispatch (already implied by the constraints); SoA layout is SIMD-friendly by default — worth checking backend autovectorization.


## Open / Deferred Items

- I/O surface (input, audio, asset loading, save files, network transport) — not excluded by the design, just not yet specified as host-exposed capabilities.
- Tooling/authoring ergonomics at scale (editor support, debugging, iteration speed) — flagged as the likely actual ceiling for "full game" scope, more so than language expressiveness.
- Serialization/networking — should be declarative per-component-field (sync policy, replication), sharing metadata with the read/write query system.
- Entity relations — treated as core to the ECS itself, not the scripting language; scripting layer just needs clean syntax sugar over whatever primitive the engine exposes.
- Error/panic semantics for script faults (bad handle deref, filter violation) — should fail predictably (abort that system's tick + log), not crash the runtime.
- Hot reload — considered an engine-side concern (how the runtime handles reloading script code/data), not a language design concern.
- Bounded execution (loop/recursion limits) for determinism — noted as needed since there's no GC pause to blame instead, not yet fully designed.

## Prior Art Referenced

- StaticEcs (Felid-Force-Studios, C#) — inverted hierarchical bitmap ECS; the storage-stability property this design leans on.
- Vale — generational references, near-identical to the entity handle scheme here.
- Austral — linear types + region-based memory, no GC.
- Lobster — compile-time refcounting elision (infers scope-bound vs. needs-refcounting), same split used here for handles.
- Shader languages (HLSL/GLSL) and Unity DOTS/Burst — existing proof that "no heap, primitives/structs only, bounded lifetimes" is a powerful-enough constraint set for real work, not just a toy restriction.
