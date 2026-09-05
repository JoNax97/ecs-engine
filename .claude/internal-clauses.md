# Internal clauses

Agent-managed rationale index. Not spec, not for a human reader. Holds what the docs leave implicit: what a decision rests on, what breaks if it is reversed, what was rejected and why. Terse by design; drop anything that would not change a future decision.

- One entry per decision, under the doc that states it; Language Spec subdivides by that doc's own sections. Citations sit on the line under the heading.
- `<- X` = rests on X. `-> Y` = Y breaks if reversed. Other bullets free-form.
- Citations name the file (`Language Spec.md#storage`); an unqualified anchor means an entry heading here. `scripts/lint-links.py` checks both.
- No dates and no attributions. An entry records what a decision rests on, not when or by whom it was made.
- Query with `python3 scripts/clause.py <pattern>` (matches heading, citation, or body); never read this file end to end. Update the matched entry in the same pass as the doc change.

---

## Engine Core

### Flat-copyable rule
`Engine Core.md#the-flat-copyable-rule`
- <- frame model: sync copies shards as opaque bytes, so anything reachable in a component must survive verbatim copy to another address space
- -> enum size fixed at declaration, hence largest-variant+discriminant payload `Language Implementation.md#enum-payloads`
- shares propagation machinery with `Language Implementation.md#load-time-constant-taint` + `Language Implementation.md#storability-taint` — change one, check the others

### Storage constraints
`Engine Core.md#constraints`
- blind-copyability <- what the memory-tier split exists to protect
- handle stability -> ruled out archetype storage, settled the model `Shelved.md#archetypetable-storage`
- shard membership by ownership/partition/serializability <- shard cannot be blind-copied one direction if ownership varies inside. partition added once sync applicability was seen to be the same kind of constraint `#shard-key-is-component-x-owner-x-partition`
- static addressability <- assumed by access-set extraction and `where` predicates; both take a field as offset+width at any depth

### Inverted bitmap storage
`Engine Core.md#storage-model`
- two sufficient arguments: handle stability, and key dimensionality — a table row carries all components, so serializability needs a third axis that per-type storage dissolves
- -> memory tracks slot-space clustering, not component-set combinatorics. badly clustered worlds cost real memory, which `#inferred-placement-class` exists to prevent
- not re-litigable on evidence: Massive shipped v19 on sparse sets and replaced them with this model in v20

### Stable identity across migration
`Engine Core.md#entity-identity`
- <- relationships are grammar with maintained backlinks `Language Implementation.md#reductions`, so slot-as-identity would break every edge on migration and need a fixup pass
- <- crossing frequency is unpredictable for a general engine. flat tax beats the cliff: slot-as-identity makes frequent migration inexpressible except as destroy/recreate
- -> cost lands only on stored-reference traversal, never on queries, which yield slots `Pending.md#what-a-stored-reference-holds`. smaller than it looks — staleness validation already costs a dependent load chain that the mapping subsumes

### Shard key is component x owner x partition
`Engine Core.md#component-shards`
- <- the three sync inputs differ in shape. ownership sets direction, partition sets applicability, serializability forbids sync outright; the first two are per-entity and dynamic, the third per component type and static
- -> serializability needs no axis: component id is already in the key, so `non_serialized` occupies its own shards by construction
- -> auxiliary data has a shard to be relative to, settling what an `external` offset is based on `Pending.md#layout-of-nested-external-data`
- partition has no engine-assigned meaning but is not semantics-free: it is in the sync path, so it cannot be demoted to a filter `Shelved.md#partition-as-a-mask-plane`
- naming: `block` was already code blocks `Language Spec.md#basic-syntax` plus a component's own layout, and `chunk` was a stray fourth name for this. "partition" over "cluster" anticipates spatial features mounting on it — watch the collision with "spatial partition" as an acceleration structure `Language Implementation.md#value-predicates`

### Inferred placement class
`Engine Core.md#component-shards`
- = archetype inference as a hint, not a structure. mispredictions cost density only; nothing relocates
- -> must stay unobservable, or changing the inference changes program meaning. no query filter, no count-by, no reflection
- -> self-healing without policy: a page re-keys once it drains empty, so bad predictions do not accumulate
- partition stays author-assigned by contrast <- it has sync consequences an inference cannot see

### Component flattening
`Engine Core.md#component-flattening`
- -> nested-field granularity in access-set extraction, free
- -> `record` nesting costs nothing at run time = records are a free abstraction, not a structural choice
- -> taint's stored field path becomes an offset

### Access sets inferred, never declared
`Engine Core.md#scheduling-and-execution`
- blocked on: analysis pass unwritten, and all scheduling assumes it

### Frame model premise
`Engine Core.md#frame-model-and-synchronization`
- load-bearing for: flat-copyable rule, `non_serialized`, bit packing, `Design Principles.md#transparent-networking-and-serialization`. stated bare in the doc; this is what falls over without it
- state sync over rollback `Shelved.md#rollback-determinism-instead-of-state-synchronization` <- relationships link arbitrary entities at runtime, so causal isolation has no static proof and rollback degenerates to simulating everything

### Structural changes take effect at the frame boundary
`Engine Core.md#frame-model-and-synchronization`
- -> presence bitmaps immutable during frame execution, so a query binding resolves once and stays valid
- -> no target resolved during a frame can be dead, destruction being structural
- -> structural mutation batches into one shard-ordered pass, not random access at statement sites
- -> a length change is structural, so an `external` field cannot grow mid-frame `Pending.md#layout-of-nested-external-data`

---

## Language Implementation

### Unbiased numeric representation
`Language Implementation.md#integers`
- <- zero-init. biased storage (`range(-10..100)` as `v + 10`) puts logical zero at bitwise 10: breaks memset entity creation, adds a correction to every op

### Unified numeric representation
`Language Implementation.md#unified-representation`
- surface split survives <- overload resolution and declared author intent both depend on it

### Division
`Language Implementation.md#division`
- split by intent, not operand type. at `f = 0` one `/` covered exact partition (index, bucket, count, wrap) and inexact ratio; only the second has a precision question, so no rounding policy reconciles them. type-split instead made an expression change meaning when a field's declared type changed
- `//` floors, not truncates, against C-family expectation: the two differ only on negatives, where truncation is a bug for spatial arithmetic. `faq-material.md#why-does--floor`
- `//` primitive, not sugar for `floor(a / b)` <- the `f = 17` intermediate cannot tell an exact result from one a hair below, so the compound form is off by one at grid boundaries. fixed-point-specific; Python's integer division is exact and has no such gap
- `%` takes the divisor's sign <- identity `a == (a // b) * b + a % b`. rejected a second pair (`rem`/`rem_euclid`): `/` has no remainder to pair with
- `/` targets fixed `f = 17`. rejected `max(fa, fb)` (SQL `DECIMAL`): two whole operands give `f = 0`, so `1 / 3` is `0`
- rejected destination-derived scale (Ada `universal_fixed`, `BigDecimal.divide`): a chained `(a / b) * c` has to push the required scale backwards
- precision degradation decided at compile time, silent. rejected runtime detection: costs a check plus data-dependent shift on every unproven op, and the build-independence it was defended on (`Engine Core.md#frame-model-and-synchronization`) comes free once the shift is baked into the artifact
- silent, not warned <- refinement is optional `Language Spec.md#numeric-types`; a warning whose remedy is "add a `range`" makes the annotation compulsory in practice. loss amount is a compile-time fact, so tooling can show it on request `Design Principles.md#show-the-machinery-in-motion`
- unrefined code is provable anyway <- storage defaults are intervals (undeclared `integer` signed 32-bit, undeclared `decimal` 32-bit at `f = 13`), so `range` tightens an existing interval. unprovable residual = genuinely unbounded by storage, not merely unannotated
- store-time range checking cannot replace the pre-shift check: an overflowed intermediate can land back inside the destination's range

### Inferred binding representation
`Language Implementation.md#inferred-bindings`
- `f = 17` for a `let` decimal <- `precision(n)` caps at 5 `Language Spec.md#numeric-types`, the widest fractional width a declaration can name. one decision; move either and the absorption guarantee breaks
- the cap <- Wasm has no widening 64x64 multiply, so a `2f` intermediate must fit 64 bits. `f = 17` leaves 29 integer bits; `f = 24` leaves 15, which ordinary position math overflows
- rejected synthesizing the wide multiply, and `v128`: wasm3 has neither i128 nor SIMD, so both cost the single-artifact property `Runtime & Deployment.md#execution-backends`
- -> reopening the cap needs static range inference over `(range, f)` deciding per expression whether a product fits. same lattice as width inference, not designed
- -> wider than 64 bits is shelved, not queued `Shelved.md#data-modeling-and-declaration-syntax`. ruling if the need appears: separate type, never a wider default, so cost stays visible
- round-to-nearest on rescale <- truncation's error is directional, accumulating rather than cancelling; toward-zero is also the costliest mode in fixed point (shift floors, negatives need a sign-dependent bias)

### No infinity or NaN
`Language Spec.md#arithmetic`
- <- no bit patterns to spare: a scaled integer reserves none, where IEEE 754 spends an exponent value. alternative to halting is a silently wrong number, not a placeholder
- -> comparison is total: no `NaN != NaN` case in sorting, deduplication, cached comparisons
- -> a silently wrong value is worse than a halt here: state is bulk-synchronized, so a wrong number desyncs peers instead of reporting itself

### Two-pass load-time checking
`Language Implementation.md#load-time-elimination`
- <- a single skip-if-false walk lets code behind a disabled optional import rot undetected. constraint dies if optional imports do
- elimination-is-not-a-guarantee gap wants a tooling answer (surface what was stripped), not a spec guarantee; pinning it would over-constrain the backend. `Pending.md#compilation-and-backend`

### Taint mechanisms
`Language Implementation.md#load-time-constant-taint`, `Language Implementation.md#storability-taint`
- one implementation, two rules. offending field path stored at declaration time
- storability is decided by handle kind, not flatness: entity and component handles unstorable and taint their container; runtime-owned collection references storable at any depth, taint nothing. blind-copyability itself needs no taint — an author cannot install a reference into stored data

### Incremental compilation
`Language Implementation.md#incremental-compilation`
- <- hot reload `Runtime & Deployment.md#hot-reload`. stable linkage exists only to make single-module recompilation viable

### Query evaluation reuse claims
`Language Implementation.md#reductions`, `Language Implementation.md#codegen-notes`
- `count` and cardinality: population counts and relationship counters already maintained by the storage layer
- relationship equality: reuses the backlink bookkeeping that keeps mutual relationships in agreement
- monomorphization affordable for the same reason a per-label bitmap is: enum labels are a small closed set
- all three instance `Design Principles.md#no-general-indexing-or-materialization` — a fast path qualifies only when it mounts on infrastructure the engine already maintains

---

## Language Spec

### Non-goals

#### Non-goals section
`Language Spec.md#non-goals`
- purpose is calibration, not justification; the *why* stays in `Shelved.md` and here
- entry condition: settled absences only. `null`, exception propagation, threading excluded — still open in `Pending.md`
- not for small feature absences (unary `++`, operator overloading, dot-calls, macros) — lookup answers, would become a dumping ground
- load-bearing negatives do not live here: a rule a checker enforces goes where it bites, attached to the positive rule it constrains

#### Heterogeneity only behind a handle
`Language Spec.md#non-goals`, no universal type
- <- layout, not type system: one stride cannot cover several layouts, so mixed types in a contiguous buffer need indirection or discriminant+largest-variant padding. monomorphization does not help — each copy is still homogeneous
- <- exactly one indirection exists, the handle `Language Spec.md#data-modeling`, uniform-width by construction. so `Component[]` is admissible where a mixed value array is not, with no boxing and no padding
- -> rules out `any`; sends component packs and `print` to `Pending.md#data-modeling-and-declaration-syntax` rather than to a universal type
- -> `enum` is the sanctioned *closed* heterogeneous form (largest-variant, flat-copyable, no indirection). the ban is on open heterogeneity, not tagged unions
- enforced per-construct where it bites, deliberately not stated as a positive rule in `Language Spec.md#data-modeling` — every construct that could violate it already carries its own rule

### Basic Syntax

#### One bracket form for three roles
`Language Spec.md#basic-syntax`
- field lists, construction and calls all take `()` <- `define` marks declarations, and there is no overloading across the type and proc namespaces, so resolution is unambiguous. reverse either premise and a second bracket form has to come back

#### Statements and expressions
`Language Spec.md#statements-and-expressions`
- expressions never contain statements <- no lambdas or closures `Language Spec.md#procedures`; a lambda is the construct that would put a statement body in expression position. statements still nest by containment
- a call is the only form that is both <- `create`, `delete`, `match`, `fail`/`assert` are statement-only and value-producing `if` is the ternary spelling, so the rule constrains calls alone. `a + b` is excluded by not being a statement, not by a purity test
- side-effect requirement <- inferred procedure purity `Pending.md#systems-scheduling-and-parallelism`; stateable now, checkable once that lands

#### Casing convention
`Language Spec.md#identifiers`
- component access keeps the type's own casing <- same symbol in `with Health`, `create Entity with Health(...)`, `if e has Health`; lowercasing it in access position alone makes one symbol change case by context
- advisory, not enforced. collisions are prevented instead by a proc not being allowed a type's name `Language Spec.md#procedure-overloading`

#### ASCII identifiers
`Language Spec.md#identifiers`
- <- cost, not semantics: Unicode needs NFC normalization and confusability handling (`é` as one codepoint against `e` plus combining accent; Latin `a` against Cyrillic `а`). machinery bought for a problem declining Unicode does not have
- does not rest on the casing convention — casing is advisory, so caseless scripts only ever affected style

#### Explicit declaration
`Language Spec.md#variables`
- <- closes the pit of failure where a misspelled name silently declares a new binding
- `let` carries no annotations <- it means "representation does not matter", honest only where the generous representation is free: true of a stack slot, false of storage
- -> `let` banned at the top level, file state being laid-out storage. reverse the premise and the ban goes with it
- file-level variables declared like fields, but bare variable-size data is dynamically backed rather than annotated <- placement opts a *field* into inline storage and file scope has no enclosing layout

#### Name first, then type, then refinements
`Language Spec.md#variables`, `Language Implementation.md#declaration-grammar`
- <- the annotated type must be one contiguous liftable unit now that it appears as a type argument: `Array(integer range(0..999), 8)` against `integer ammo range(0..999)`, where the identifier splits type from annotations
- rejected type-first with leading annotations (`integer range(0..999) ammo`): wedges second-order material between name and type
- rejected colon (`ammo: integer`): spends a punctuation mark nothing else needs, and `define` has no natural colon
- rejected trailing annotations on `define`: multi-line bodies put `ordered` far below the name it modifies
- -> `define` and field declarations are one production, differing only in the type token — `Effect enum ordered`, `gold integer range(0..999)`
- access is infixed between `define` and the name <- it qualifies the act of defining, not the thing defined, hence never valid in a field or parameter list. only infix element in the grammar
- modifiers lead, and field lists take no prefix at all <- every leading candidate (`ordered`, `mutual`, visibility) appears only on a `define`. left-aligned field lists removed the last argument for the colon
- -> colons leave the grammar; named construction and tuple labels take `=`. safe because statements cannot be operands, so `=` is never an expression in an argument list, and fields cannot declare defaults. closes the named-argument-separator question
- open: relationship cardinality (`define Targets[8] relationship`) and bulk creation (`create Entity[count]`) — bracket forms that survived collections moving to `Array(T, n)`, neither fitting the refinement grammar

#### `let` declares every variable; omitting the type infers it
`Language Spec.md#variables`
- <- paren-less calls are legal statements, so a bare `health integer` is equally a one-argument call; the keyword disambiguates. same reason as Go `var`, Rust/Swift `let`
- -> collapses two declaration forms into one; "annotations require a written type" falls out instead of being stated
- fields and parameters keep no keyword <- neither appears in statement position
- `let` over `var` despite the Rust/Swift immutability association <- immutable bindings here have no keyword of their own, so the conflict fails loudly; the target audience (GDScript, Unity C#) arrives with no prior
- rejected a third form for a runtime-assigned, non-reassignable local (Rust `let`, Kotlin `val`): changes no representation, adds no operation, enables no codegen. if silent repointing of a collection handle proves real, fix at `#assignment-writes-what-the-left-side-denotes`
- file-scope `let` takes visibility in the same slot `define` does — `let private score integer`

#### Bindings are immutable
`Language Spec.md#bindings`
- forced by narrowing: `is Heal heal` binds a live reference, so `heal = other` is ambiguous between rebinding and writing through. one rule covers parameters, loop variables, query bindings and `is` bindings
- -> parameters always by reference, copied only where the body writes into them `Language Implementation.md#parameter-passing`. writing into the parameter's own storage is the only channel through which a callee could observe how it was passed, and immutable bindings plus no reference parameters plus no closures leave it the only one. reverse any and the copy decision stops being static
- constrains the identifier, never the data: `target.Health.current += damage` and `heal.amount = 0` stay ordinary writes

#### Negated presence and narrowing
`Language Spec.md#operators`
- single operators, not `not` applied to a result <- otherwise a second spelling of an existing composition, the objection that shelved dot-sugar
- `has no` and `has not` both accepted for one operator <- English needs both, `has no Shield` before a noun and `has not Moved` before a participle, and tags are frequently participles. the one deliberate two-spelling case
- `no` is reserved <- casing is advisory, so a component could legally be named `no` and `e has no` would be ambiguous
- <- direct precedent: SQL `IS NOT NULL`/`NOT IN`, Python `is not`/`not in`
- -> removes a precedence question: `not target has Shield` needs `has` to bind tighter than `not`
- nothing binds on a negated form; as its own operator that reads as obvious rather than as a carve-out of `not (effect is Heal heal)`
- `without` in a `for` clause is the structural form of the same test: a preposition modifies a binding in a declarative clause, a verb forms a boolean expression
- open: whether `not <expr> has <T>` is illegal or merely non-idiomatic. leaving it legal costs a third spelling examples drift toward; banning it is a rule about where `not` may apply that nothing else needs
- `!=` stays separate: it compares values, `is not` tests a label

### Control flow

#### Match arms
`Language Spec.md#conditional-statements`
- an arm is a comparison with the subject as implied left operand -> `<=`, `in` and label tests are one grammar, not a pattern sublanguage
- a bare operand implies the operator too, resolving to the operand's equality — `==` for a value, `is` for a label — reusing the existing split `Language Spec.md#operators`. binding falls out, `is` being the only binding operator
- right operand must be constant <- constant arms over enum labels stay dispatchable (jump table, per-label bitmap); arbitrary expressions make `match` sugar for an `if`/`else if` chain. C# and Rust draw the same line
- no exhaustiveness, order is semantic, overlap legal <- no compiler-known totality anywhere else in the language

### Primitive Types

#### Strings: immutable, unbounded, always external
`Language Spec.md#strings`
- ratifies more than it restricts: no `char` type, so character-level mutation was already unspellable; interpolation constructs a new string; `label.tag = "x"` is a field write and stays legal
- -> settles copy-against-share `#collections-are-handles-strings-are-values`: no program can observe aliasing, so sharing is an implementation choice (refcount, intern table, arena) and placement stays a pure cost annotation
- does not settle serialization: a runtime-managed buffer is still not flat-copyable, so an `external` string field crossing the sync boundary is open on its own terms
- concatenation banned for cost visibility, not capability: interpolation is one site, one O(n) pass, compile-time-known part count, where `((a + b) + c) + d` is O(n²) with no individual site looking expensive. `+` stays arithmetic-only
- accepted cost: accumulation is O(n²) with interpolation alone -> an accumulator type is a consequence of the rule rather than an extra. semantics settled in `Pending.md#text-accumulation-has-no-construct`, only the spelling open. every immutable-string language ships one
- no `capacity(n)`, no placement choice <- a character count gives no byte count under variable-width encoding, so an inline string's footprint and therefore its default placement are unevaluable, and worst-case reservation put a 16-character string at 64 bytes. removing inline strings deletes the dependency and drops `Pending.md#string-encoding` back to deferrable

#### Collections are handles, strings are values
`Language Spec.md#collections`, `Language Spec.md#strings`
- one question, opposite answers, same reason: strings are immutable so a copy is unobservable and the runtime may share; arrays are mutable so nothing can be elided and copy-on-assignment would be a real O(n) cost, out of step with Java/C#/JS/Python
- every collection, inline and `external` alike <- otherwise a type changes nature by how it is declared, the exact rule that made placement an annotation `Design Principles.md#compose-constructs-not-values`
- rests on storage location and value/handle semantics being independent, which `component` already demonstrates — inline in ECS storage, handle semantics anyway
- binding references, field assignment copies: `let s = inv.slots` aliases, `inv.slots = other` stores, and a handle is never stored
- -> removes a case from the parameter rule: a `List(integer)` parameter is a reference with no copy-if-written analysis
- departs from Odin, which makes fixed arrays values and reserves reference semantics for slices <- Loom has no slice type `Pending.md#slices`, so it cannot make that split. revisit if slices arrive

#### Array literals use brackets
`Language Spec.md#collections`
- <- an unnamed tuple literal and a parenthesized homogeneous list are the same text; disambiguating by homogeneity would make a literal change category when an element's type changes
- <- `[]` already means "N of this type", so the literal matches the declaration form. cost: `[` now opens a literal as well as closing a declaration bound
- no separate list type <- an unnamed, homogeneous, indexable sequence is an array with a literal-inferred bound

#### Collection types, and placement as an annotation
`Language Spec.md#collections`, `Language Spec.md#storage`
- always-full against counted is forced by zero-initialization: fields have no defaults, so a lookup table must zero-init full and an inventory must zero-init empty. one type cannot do both — starting empty makes matrices need a fill step the type cannot require, starting full makes `append` on a fresh inventory fail at capacity
- three orthogonal axes: population (always full against counted), extent (static against runtime), placement (`inline` against `external`). `Array(T, n)` fixes extent in the type, `Array(T)` takes it at creation with runtime-checked indices, `List(T)` varies its count and takes `capacity(n)`. counted-by-N-dimensional is the one empty cell, appending to a rectangle being meaningless
- placement is independent of count: `Array(decimal, 1024) external` is always full, fixed extent, never resized, allocated once — the cheapest runtime-managed case in the language
- the placement axis is intra-element against inter-element locality, not "this data has no fixed size": inline pays on every query iteration whether the collection is touched or not, external keeps components small
- defaulted, not mandatory <- an uninformed author forced to decide is worse than a good-enough default. safe because the default is self-limiting: only small data is inlined, so large inline data in a hot query is unreachable without asking for it, and a wrong default costs one indirection. threshold deferred `Pending.md#the-inlineexternal-default-threshold`
- users build *on* the primitive, never beneath it: a ring buffer or sparse set over `List(T)` is ordinary code, but a collection managing its own storage needs allocation and a pointer, both non-goals
- spelled as a type constructor, not brackets <- bracket-on-the-identifier is the only declaration form putting type information on the name; everything else is `type identifier annotation`. parens not angle brackets, `<`/`>` being relational operators
- `Array`/`List` is a builtin constructor, **not evidence that generics exist** (same position Swift holds for its stdlib) — worth pre-empting, since an author will otherwise infer `Inventory(T)`. monomorphization is mandatory rather than an optimization: the flat-copyable rule and static access-set extraction both need layout at compile time
- naming decided imperfect and shipped: `Array` splits by tradition (fixed in C/Rust/Odin, growable in JS/GDScript), rescued by arity disambiguating at the use site — `Array(Item)` demands nothing, `List(Item, 30)` is unwritable
- rejected `Fixed`/`List` (`Fixed` names the count being constant, not the container's nature) and `FixedArray`/`DynamicArray` (verbosity on every read against ambiguity once per reader)
- rejected `integer(30)`: no slot for element refinements, and collides with construction and cast syntax
- -> promotes `Pending.md#slices` from 3 to 4: with three collection forms and no subtyping, a view is the only spelling for a procedure reading more than one
- -> strings sit outside the placement system entirely `#strings-immutable-unbounded-always-external`

#### Sets and maps
`Pending.md#sets-and-maps`
- containers under the flat-copyable rule <- a hash-backed container needs fixed size and no pointers to be a component field; at best `external`, at worst outside a component entirely. tuples do not change this — they are stack-only

#### Tuples
`Language Spec.md#tuples`
- stack-only <- a storable tuple would need a position under the flat-copyable rule and would then be a nameless `record`. removes the storage, schema and taint questions rather than answering them
- no annotations on elements <- annotations attach to declarations and a tuple literal is not one. second reason a tuple cannot be a component field: a `string` or array in a `define`d type must state its storage `Language Spec.md#storage` and a tuple has nowhere to state it
- cap of four <- ordinal accessors `first`..`fourth` then cover the space, so no `.0` and `[]` keeps its single meaning. past four the answer is a `record`. reverse the cap and positional access has to come back
- names documentation-only <- the `signature` precedent, matching by type and order. -> named and unnamed tuples are the same type, so the no-mixing rule constrains *literals*, not types
- implicit construction, never implicit deconstruction <- the asymmetry kills the spread/nest ambiguity: `f(10, 5)` and `f((10, 5))` are different types and nothing flattens. construction ranked as a coercion so an exact parameter match wins `Language Spec.md#procedure-overloading`
- deconstruction is an explicit construct <- otherwise "never taken apart implicitly" contradicts `let div, mod = divmod(10, 3)`
- not iterable <- walking a heterogeneous sequence needs compile-time unrolling typechecked per element type, which is generic-code machinery and would make tuples depend on `Pending.md#data-modeling-and-declaration-syntax` generics

### Numeric Types

#### Changing precision
`Language Spec.md#changing-precision`
- the line is the declared type keyword, not lossiness: narrowing within `decimal` is lossy too and stays implicit; crossing to `integer` is what an author reads at the use site
- no cast syntax at all <- a cast-shaped spelling imports C truncation, and neither conversion truncates (implicit rescale rounds to nearest, `//` floors). three behaviours in play, so the operation is named rather than defaulted
- -> `precision(0)` must be unspellable, or one representation follows two conversion rules depending on the declaring keyword `Shelved.md#data-modeling-and-declaration-syntax`
- rejected making all narrowing explicit: storing a wide expression into a declared field is how ordinary arithmetic terminates

### Program Structure

#### File state is non-persistent
`Engine Core.md#memory-tiers`
- <- Unmanaged memory sits outside every shard and the frame model synchronizes shards. non-sync and non-serialization are consequences of the tier, not separate rules
- carried by scope rather than a keyword <- failure modes correlate with misuse: a genuine cache is rebuildable so reload wiping it is invisible, while secretly authoritative state breaks loudly on first reload. same split as Bevy `Resource`/`Local`, flecs world singleton/`ctx`
- -> when systems become first-class, variables stay module-level. a system is not addressable, so `System.variable` would make it addressable through the back door

### Data Modeling

#### Values and handles
`Language Spec.md#data-modeling`
- two behaviours, not three: entities, components, collections and future resources are handles, everything else is a value. collections are where "runtime-owned" stops being synonymous with "world-owned" — a local collection literal is a handle over general runtime memory `#collections-are-handles-strings-are-values`
- supersedes provenance-inferred backing: the destination of a write is a fact about the type, not about where the identifier came from `Design Principles.md#no-hidden-costs`
- validity is structural, not checked, for entity and component handles <- neither can be stored in a component or file state, nor held across a frame boundary, so it can never refer to data that is gone. property of those two kinds, not of handle-ness — a resource handle is long-lived and needs a checked story `Pending.md#data-modeling-and-declaration-syntax`. the spec states neither
- -> settles the parameter question: a component parameter is a view because every component identifier is, a value parameter is a copy. what the author learns is the value/handle split, not a calling convention
- -> deferred structural change (create into a temporary region, move at the boundary; delete deferred to the same point) is what makes the guarantee hold, arriving as a consequence rather than a feature. ties to `Pending.md#errors-and-control-flow`

#### Assignment writes what the left side denotes
`Language Spec.md#data-modeling`
- a variable's value *is* the handle so it repoints; a field names storage so it writes contents. the asymmetry comes from what a field is, not from a case carved out for arrays
- rejected declaration-binds/assignment-always-stores (C++ reference semantics): collapses the variable/binding distinction for handle types, and C++/C# make it opt-in at the declaration (`&`, `ref`) where Loom has no marker
- -> field assignment stores for inline and `external` fields alike. an `external` field does hold a reference and could be repointed, but that would make placement change semantics, which `#collections-are-handles-strings-are-values` forbids. the two brace each other
- -> **an author can never produce a stored reference**: handles repoint only on the stack, and inside stored data the reference is the runtime's with only contents changing. this is what makes handles inside components workable — every shard-relative offset is runtime-made, so flat-copyability rests on an invariant rather than a prohibition, and the static-discriminant blocker in `Pending.md#layout-of-nested-external-data` is answered on the correctness side
- accepted: no O(1) handoff into storage. not a cost of these semantics — flat-copyability needs data at specific addresses, so inbound data is copied regardless. eliding the copy for build-then-store is implementation freedom (no closures, linear execution, static access sets); the contract must only avoid promising the built buffer stays a distinct buffer
- absence: an `external` field always designates a runtime-owned buffer. if absence is ever needed it is a sentinel handle state, not a null, and belongs to resource-like handles — plain collections must not inherit a presence check `Pending.md#memory-tiers-handle-validity-and-nullabsence-semantics`

#### `record`, not `value`
`Language Spec.md#records`
- renamed <- `value` carried three jobs: the keyword, the assignment-semantics category (which also covers numerics, strings, tuples and enums, so the keyword was a strict subset), and "what an expression produces". only the first was nameable; the category keeps the word `value`
- `record` <- Pascal, Ada, F#, Elm all use it for a named-field aggregate with copy semantics, and it is SQL vocabulary `Language Spec.md#scope`. plain English where `struct` would cost `Design Principles.md#readable-by-non-engineers`
- rejected `data` (components and enums are data too) and renaming the *category* to copied/shared ("handle" is still needed as a noun — lifetime, validity and identity equality are statements about one)

#### Enums
`Language Spec.md#enums`
- explicit label values dropped <- schema pre-agreement `#schema-agreement-is-a-premise-not-a-per-feature-concern` means no number needs to be stable outside the language. ordinals also keep entity-attached labels dense, so component ids stay `base + offset`
- first label is the zero value <- everything else in the language zero-initializes to a valid value. -> declaration order is semantic, for the default and for label ordering
- bare-name construction of a payload label (`effect = Heal`) is not an enum rule <- it follows from a type being constructible by name alone `Language Spec.md#construction`, and ranges must include zero `Language Spec.md#ranges`, so a zeroed payload is always legal
- whole-payload binding (`is Heal heal`) over positional destructuring <- `type name` is the language's own declaration shape, so no pattern sublanguage is introduced. cost: `heal.amount` for single-field payloads
- rejected one declared type per payload (Zig, Odin): forces a `HealData` declaration for a single integer
- payload unreachable without a binding <- an enum value has no fields, so no fallibility machinery is needed
- enums and tagged unions stay one construct <- the dividing line is whether the label's *number* is part of the concept. revisit test: count "if payload-free" carve-outs. currently zero; two or three means it is two constructs sharing a keyword

#### `ordered` enums
`Language Spec.md#enums`
- fixes a trichotomy break: label order gave `<` and structural equality gave `==`, so two values with one label and different payloads made `a < b`, `a == b` and `a > b` all false, breaking any sort or clamp
- lexicographic label-then-payload, as Rust, Haskell and Swift. what they have is *opt-in* derivation, so they need no rule about payload orderability; annotations are Loom's equivalent surface, and "every field is orderable" is one recursive compiler check rather than a constraint system
- chosen over restricting relational operators to payload-free enums <- that would be the first "if payload-free" carve-out, the tripwire for enums and tagged unions being one construct
- chosen over inference <- adding a payload field would silently remove `<` from every use site, with the error landing away from the edit
- rejected exposing the ordinal as `.order`: re-exposes the label's number as a value, so `order + 1` and storing it become spellable and reordering labels stops being free
- extending `ordered` past enums lives in `Pending.md#generics-and-traitconformance-syntax`: the live question is *how a capability is authored*. direction: the annotation is a request the compiler checks by finding a procedure of shape `Compare(T a, T b) returns integer`, reusing `signature` rather than adding conformance machinery. cuts against traits being fields-only and conformance explicit
- no label-only comparison of two runtime values. `is` covers the named case, and sorting or grouping by kind falls out of label-first ordering. deduplication by kind is an accepted hole `Shelved.md#data-modeling-and-declaration-syntax`

#### External data nests at any depth
`Language Spec.md#storage`
- settled contract with the layout left pending `Pending.md#layout-of-nested-external-data`: **legality is promised, cost is not**. correctness is settled <- an author cannot install a stored reference `#assignment-writes-what-the-left-side-denotes`, so every nested reference is runtime-made and the discriminant is static. layout is downstream of a 5-rated storage model
- two of three blockers were discharged elsewhere: the static discriminant by the stored-reference rule, and "promotion must be an explicit named operation, never silent assignment" by field assignment storing contents, which makes writing a record with nested external fields a deep copy. only layout survives
- -> retires the flat-copyable taint's disqualifying job `Language Implementation.md#storability-taint`. it is not a locator for copy fixups either — static addressability already yields a component's references by walking the flattened layout
- forced by strings becoming always external, which would otherwise make any `record` holding a string component-illegal

#### Comparison and equality pass
`Language Spec.md#comparison-semantics`
- `==` is exempt from the cost rule for the same reason `in` is: cost follows the operand's declared type, and a string is always external, so there is no cheap twin to confuse it with
- components compare structurally though they are handles <- handle-ness governs aliasing on write, not equality, and comparison is across entities in the majority case. identity equality would make `a.Health == b.Health` false for any two distinct entities
- entities compare whole, generation included <- an entity is opaque and has no fields, so identity is all there is. the rule is *equal handle value means the same element*, which forces canonical encoding onto the storage pass `Pending.md#entity-identity-and-generation`
- collections check element type statically and element count at run time <- `Array(T, n)` carries its count in the type, `Array(T)` and `List(T)` do not, so count is not part of comparability
- relational stays numeric-only plus `ordered` enums. string ordering dropped: cost stopped being an argument once `==` was exempt, and byte order reads as alphabetical without being it

#### `in` takes any collection-like operand
`Language Spec.md#membership-semantics`
- reverses the earlier cost-based "range and nothing else": the collection is named at the site either way, so cost follows a declared type and is not hidden, and a lint covers what the rule protected `Design Principles.md#give-visibility-into-performance-and-costs`
- surviving reason is symmetry: `for x in collection` and `if x in collection` are one operand shape in two positions — a property of the language, where the cost argument was a property of one operand pair
- Odin restricts `in` to O(1) operands but has maps *and* bit sets, the Python `list`/`set` trap. trap accepted knowingly: smoothness over cleanliness `Design Principles.md#clean-clear-smooth`
- rejected `collection contains x`: no cost visibility gained, collides with `has`, and has no loop-position form
- strings are the one operand symmetry does not justify — `in` is subsequence containment there, and there is no `char` to iterate. kept anyway, following Python; strings become iterable once slices exist `Pending.md#data-modeling-and-declaration-syntax`
- literal ranges only for now; a named range follows once value constants are settled `Pending.md#data-modeling-and-declaration-syntax`

### Procedures

#### Paren-less calls
`Language Spec.md#procedures`
- zero-or-one argument, statement position only <- lets standard-library procedures read as keywords (`test_and_halt`), shrinking the built-in surface instead of growing it
- a bare name in argument position is a reference, never a call <- otherwise `baz foo` runs or does not run `foo` depending on the callee's parameter type, which is type-directed hidden control flow. cost: `print get_score` is an error, `print get_score()` is the spelling
- no marker on the reference form, no sigil or keyword <- every language needing none (Python, JS, Go, Rust) has calls always taking `()`; the ones that marked it (Pascal `@Foo`, VB `AddressOf`, Ruby `method(:foo)`) are exactly those keeping general paren-less calls. the marker is the price of the call rule, not a fix for it. cheaper lever: narrow where a paren-less call is legal `Pending.md#data-modeling-and-declaration-syntax`
- residual ambiguity needs a zero-argument proc passed where both a signature type and its return type fit — rare enough to reject outright if it arises
- removing the paren-less rule costs less than it looks: the language's voice is keywords (`create ... with`, `delete`, `fail`, `on`, `for`/`where`/`do`), none of them calls, so the only real beneficiary is `print`
- Python 2 is not prior art despite `print "x"`: `print` was a reserved grammar production, not a paren-less call, so the ambiguity never arose and the cost surfaced as `f = print` being unwriteable

#### No dot-call syntax
`Shelved.md#data-modeling-and-declaration-syntax`
- -> `.` means exactly one thing, reaching into data
- -> the casing convention stays advisory: dot-sugar on an entity would need a lookup order between component types and procedures, or compiler-enforced casing
- does not weaken the traits argument — overloading covers "one name, many types" `Language Spec.md#procedure-overloading`
- cost: nested calls read inside-out, and the designated answer (pipe syntax) is shelved too `Shelved.md#data-modeling-and-declaration-syntax`. if the pressure returns, reopen the pipe form, not dot-sugar
- -> `then` is unclaimed, and `Pending.md#errors-and-control-flow` wants it for `if cond then a else b`

#### Procedure overloading
`Language Spec.md#procedure-overloading`
- parameter names excluded <- a name is not part of the call's type information, so including it would let two indistinguishable call sites resolve differently
- constrained numerics resolve as their base type <- constraints refine representation, not identity `Language Implementation.md#unified-representation`
- the numeric ranking ("prefer the smaller scale change") lives in the implementation doc <- consequence of the scaled-integer representation, not a surface rule
- a type and a proc cannot share a name <- identifier uniqueness within scope already forbids it, no namespace rule needed. reverse uniqueness and `Health(current = 100)` is ambiguous between construction and call
- -> covers "one name, many types" alone, so traits are needed only for generic code `Pending.md#data-modeling-and-declaration-syntax`
- open: a hand-written concrete generic query taking precedence over the autogenerated one is a specialization rule, to be squared with these when generics are designed

#### Signatures
`Language Spec.md#signatures`
- the rule is *a procedure reference must be derivable from source, not from data*, not "procedures are not values" — the value framing would ban comparators and sorting, which are legitimate
- <- static access-set extraction `Engine Core.md#scheduling-and-execution`: a statically resolved reference propagates the callee's access set exactly, where a reference read from data makes the callee underivable and a conservative union is pessimistic invisibly at the call site `Design Principles.md#no-hidden-costs`
- no anonymous proc literals <- with no literal there is no argument position to nest one call inside another's, so callback pyramids are unspellable rather than discouraged. also keeps the call site naming intent (`by_weight`)
- anonymous *listener* blocks are not a counterexample: top-level only, no capture, statically bound, cannot be registered or removed. an unnamed declaration, not a value
- no stack-level binding of a signature parameter <- that is where propagation degrades from exact to a union and the call stops inlining to one direct callee. an `if` expresses the same thing
- separate `define signature` rather than Pascal-style inline in the parameter list <- the inline form is dense for a non-expert reader. cost: one extra declaration per signature
- `signature`, not `delegate` <- C# delegates are storable in fields, multicast and rebindable at run time, all refused here; every language with a *named declaration* for the concept (C#, Go, Turbo Pascal) made it storable
- PascalCase <- a signature sits in type position, and `sort(items List(Item), before item_comparison)` reads as two parameter names in a row

### Entities

#### Proven presence
`Language Spec.md#component-access`
- component access is infallible exactly where a construct has proven presence — `with` in a query, `has X x` in an expression. bare `e.Health` stays legal and fallible
- `has X x` makes the access infallible *without* flow-sensitive checking <- validity comes from the construct that created the binding, not from a fact carried across statements
- -> no fact to invalidate: an intervening call that might remove the component cannot make the binding illegal, which is what a narrowing checker would have to track through purity and access-set information
- open: whether the compiler *also* narrows bare access inside a guard `Pending.md#data-modeling-and-declaration-syntax`. the enum case declined narrowing on syntax grounds, not checker cost, so the door is not closed

### Queries

#### Query clauses are the primary form, not an alternative one
`Language Spec.md#queries`
- primary <- absence of the competitor: no closures `Language Spec.md#procedures` means no `.Where(x => ...)` chain is constructible, and no dot-call sugar `Shelved.md#data-modeling-and-declaration-syntax` means no chain to hang it on. C#'s query syntax is vestigial precisely because method chaining is always available
- -> the two shelvings are load-bearing here, not aesthetic. reverse either and the clause form acquires the competitor that made C#'s vestigial
- cost direction is inverted from C#'s: LINQ's lambdas are why it allocates closures and enumerators, where a clause body is syntax rather than a value, so predicates capture nothing and the declarative form is the *fast* one
- -> clause vocabulary can grow on cost grounds with no ergonomic escape hatch existing. makes reductions worth reopening `Pending.md#queries-and-predicates`; the admission rule is the whole gate — fixed-size result free, variable-size result must show its buffer

---

## Runtime & Deployment

### Console backend choice
`Runtime & Deployment.md#execution-backends`
- console portability is not blocked by Wasm as such; the constraint is JIT, forbidden by certification. AOT and interpretation both sidestep it while keeping one artifact

### Schema agreement is a premise, not a per-feature concern
`Engine Core.md#frame-model-and-synchronization`
- peers pre-agree on every data schema — component ids, layouts, enum ordinals — and synchronization transfers raw bytes against it, so no wire-level identifier needs independent stability
- -> declaration-order ordinals are safe for enums `Language Spec.md#enums`
- saved data: store the schema alongside the raw data and remap on load, rather than freezing identifiers at the language level. version skew handled once, in the save path
- reverse the pre-agreement premise — a peer or save carrying data written against an unknown schema — and stable identifiers become load-bearing everywhere

---

## Design Principles

### Clean, clear, smooth
`Design Principles.md#clean-clear-smooth`
- descriptive, not aspirational: every pairwise conflict already had a decided instance — clean against clear by bare-name-as-reference `Language Spec.md#procedures`, clean against smooth by `has no`/`has not` being one operator with two spellings `Language Spec.md#operators`, smooth against clear still open in the three `where`-shaped constructs `Pending.md#data-modeling-and-declaration-syntax`
- a frame over the existing principles, not three more entries <- appending would make the three read as peers of the commitments they generate. sorting: clarity covers `Design Principles.md#no-hidden-costs` and `Design Principles.md#data-layout-follows-declared-intent`, cleanliness `Design Principles.md#minimize-language-breadth-and-feature-creep`, smoothness `Design Principles.md#readable-by-non-engineers`
- the precedence is the load-bearing part <- three qualities without an order justify any decision. clear-then-smooth-then-clean is read off the record: clarity has not lost a ruling, cleanliness lost the one time it was tested against smoothness
- explicitly not brevity <- terseness conflicts with static strictness. resolves once the axis is friction rather than length: strictness lands at declaration sites, written once and read often. same shape as SQL's verbose DDL against readable DML
- strictness generates little notation here <- the parts of Rust that produce dense syntax (lifetimes, borrows, generics, `?`, closures) are all non-goals. Go is the evidence that density arrives with generics specifically, which is where the frame gets tested next `Pending.md#data-modeling-and-declaration-syntax`

### Compose constructs, not values
`Design Principles.md#compose-constructs-not-values`
- the syntactic/value split is the whole content <- without it the principle contradicts no-closures `Language Spec.md#non-goals` and `Design Principles.md#no-general-indexing-or-materialization`, both refusals of composability and both correct. syntactic composition resolves at compile time and costs nothing; value composition materializes intermediates
- kind against annotation is stated as identity, not a checklist <- the earlier "invariant the runtime maintains, or a matching primitive queries can use" was `relationship` described twice, and it fails its own stress test: `define Target component targets(8) mutual` is spellable, so a can-this-be-annotated test rejects relationship
- worked cases the tells were read off: `integer`/`decimal` two kinds because `precision(0)` had to be unspellable `Language Spec.md#changing-precision`; `tag` a kind because it alters how data is stored and reached, not because it lacks fields; `relationship` a kind because a kind names what a thing is, not how it is stored; `range`/`precision` annotations because behaviour is unchanged; `ordered` an annotation because it only adds an operation set
- two mechanical tells: an annotation the overload resolver cannot see is safely an annotation `Language Spec.md#procedure-overloading`; an annotation that constrains what may *contain* the declaration is not one
- -> placement closed as an annotation, costing the second tell its generality <- a type may not change its value/handle nature by where it is declared `Language Spec.md#data-modeling`, so the record-in-component restriction is a layout consequence of having no inline size, not a semantic one. the tell has to read *semantic* containment
- -> `query` fails on identity: a query and a proc are both code that runs, so the kind names no distinct thing `Pending.md#queries-and-predicates`. pre-empts the same question for systems and commands, precedent set on the cheap case first
- first application to a *construct* rather than a kind: bulk entity creation `Language Spec.md#creation` fails the brevity reading and passes on being a different operation to the engine, one N-slot allocation against N independent ones. reusable test: "does the engine do something else", not "is it shorter to write"
- bulk creation specifics: runtime count, shared `with` list, per-entity variation dropped rather than deferred. result is an `Array(Entity)` `Language Spec.md#collections`, always full and no append, so it needed no new rule and was never blocked on arrays-as-capacity. value protected: under inverted-bitmap storage memory cost tracks entity-ID clustering `Pending.md#storage-and-memory-layout`, and this is the only construct that can guarantee contiguous IDs
- the cost guarded against is multiplication, not vocabulary size: every kind adds a row to every rule stated about kinds — visibility, storage, comparison semantics, query interaction, serialization
- distinct from `Design Principles.md#minimize-language-breadth-and-feature-creep`, which declines features outright; this accepts the capability and rejects a separate construct for it

### Linearity is load-bearing, not incidental
`Language Spec.md#non-goals`, no asynchronous execution
- broader than frames and awaiting: a body runs to completion and nothing resumes it, so any construct with a resume point is a suspension however it is spelled
- -> killed capture-free deferred execution on its own, where the cost argument could not reach it `Shelved.md#events-and-change-detection` — nothing captured means one compile-time-sized flag per site, cheap and still rejected
- same shape as the coroutine ruling and the single-use-listener ruling: three constructs, one objection

### Scripts are portable
`Design Principles.md#scripts-are-portable`
- -> makes the compile-time/load-time split tractable: if the only per-deployment variable is module presence, the load boundary can resolve everything

### Reasoning compressed out of Pending
recovery notes
- intrinsic fallibility, cost: range arithmetic becomes load-bearing type checking rather than metadata — interval propagation through the operators, decidable at the load boundary, and it must be **specified**, since an unrecognized-but-equivalent range expression degrading to fallible is the same cost cliff as the `where` predicate-shape problem. runtime cost is a branch the author wrote, no unwinding machinery, which suits AOT and interpreter alike
- intrinsic fallibility against Verse `Pending.md#errors-and-control-flow`: Verse guards every division because it knows nothing about the divisor; declared ranges make the feature affordable here, and the ergonomics invert — a required guard means the domain was under-specified, so the remedy is to state the range `Design Principles.md#domain-over-technicism`
- query as a form inside a proc: access-set extraction survives because a query stays syntactically visible and nothing callable is stored in data, which holds only because `Language Spec.md#signatures` and the absence of closures already paid for it
- erased component handles: a narrowing arm is a branch and extraction already unions across branches, so sets over-approximate — false conflicts, never missed ones
- gating on a global condition: the singleton candidate relies on unstated optimizer behaviour, the same trap as recognized-against-unrecognized predicate shapes `Pending.md#queries-and-predicates`
- conformance by proc shape `Pending.md#data-modeling-and-declaration-syntax`: prior art splits Go structural against Rust/Swift explicit `impl`, with C# and C++ operator resolution as shape-scanning precedent. standing argument against structural is that a shape match can be accidental
