## Purpose

This document states the design principles behind the Loom engine and LoomScript. It is the criterion the other specifications are judged against: where a proposal conflicts with a principle here, either the proposal is rejected or this document is amended deliberately.

It describes intent, not mechanism. How a principle is delivered belongs in the implementation spec; what an author may rely on belongs in the language spec.

---

## Clean, clear, smooth

Three qualities the design is judged on. The principles that follow are the specific commitments they produce, and are read as instances of them rather than as an unordered list.

**Clean** is about what is present: nothing in the text that does not carry meaning — no ceremony, no decoration, no redundant marks. The test is whether removing it loses anything.

**Clear** is about what it means: one reading, and that reading is the true one, cost included. The test is whether a reader can say what a construct does and what it costs without looking elsewhere.

**Smooth** is about reading motion: no snags, no special cases to stop on, a shape that holds across contexts. The test is whether the eye stops.

When they conflict, the order is **clear, then smooth, then clean**. Clarity is never traded away: a construct that reads well but hides its meaning or its cost is rejected. Smoothness outranks cleanliness, so a second spelling is admissible where it makes a construct read correctly. Cleanliness is the tiebreaker rather than a trump — it is the quality the writer notices most and the reader notices least.

Note that none of the three is brevity. Length is not a cost here; friction is.

---

## Engine

### ECS focused

Entities, components, systems, queries and relationships are the primitives the whole design is organized around, not a subsystem within it.

### Transparent networking and serialization

Gameplay code should not be aware that networking exists. It is written once and executed where it needs to be, transparently. No sync-var annotations, no RPCs, no authority plumbing.

Where the author genuinely must intervene, the intervention is declarative metadata attached to a declaration — marking a component `non_serialized`, or declaring peer ownership over a piece of data — never control flow.

### Transparent and cheap serialization

Data structures and allocation strategies are designed for blind memory copying, with no per-element processing, encoding, or pointer chasing.

### Data layout follows declared intent

The engine organizes memory so that physical layout matches the constraints the author declared. The same mechanism serves synchronization, ownership partitioning, streaming and partially loaded data, and interest management.

---

## Language

### Serve the engine objectives

LoomScript's first obligation is to honor and be conducive to the engine design requirements.

### Domain over technicism

The author expresses facts about the game; the compiler derives the technical consequences. Declaring that health ranges 0..1000 is a domain statement; choosing a 24-bit unsigned representation is not the author's job.

### Pit of success

Defaults make the safe and correct path the easy path. The best option should also be the default, the easiest or most obvious one.

### No hidden costs

Nothing executes that the author did not ask for, and nothing expensive looks free. Where something is expensive, destructive or dangerous, it should be explicit and hard to reach.

A cost derived from a data structure's nature is not hidden; the author is expected to know what their own data costs to traverse. What is to be avoided is cost that varies for reasons the code does not show.

### Readable by non-engineers

The language should be legible to designers and modders, not only to programmers. Minimal punctuation, plain English keywords, no ceremony. The domain and intent should stick out unimpeded.

### Minimize language breadth and feature creep

The language stays small by declining features rather than accommodating them. Provide handy features for the common case, and building blocks for the uncommon one. 
Reuse syntax and mechanisms across contexts when possible.

### Compose constructs, not values

Where a capability can be had by putting existing constructs together, that is preferred to introducing a new one. A construct that exists to remove ceremony from a pattern already expressible is a second spelling, and is declined.

An annotation refines a declaration; it does not change what the declaration is. A capability that changes what a thing fundamentally is, what it represents, or how it behaves earns a kind and a keyword. Everything else is an annotation on a kind that already exists.

The composition meant here is syntactic: constructs nest within one another and resolve at compile time, so combining them costs nothing at run time. It is not composition of values. Chaining operations that each yield an intermediate result is materialization, and is refused for the reason below. The two go by the same name and have opposite costs.

### No general indexing or materialization

The query language does not get generalized, SQL-style materialized result sets, and no feature justifies building general indexing machinery on its own.

Fast paths are earned case by case: a feature qualifies when it can be mounted on infrastructure the engine already maintains — presence bitmaps, relationship counters, change bitmaps — and the value is worth the complexity. Everything else stays an honestly-costed scan rather than triggering new index-building work.

### Scripts are portable

One script artifact runs on every target. Anything genuinely platform- or architecture-specific is abstracted away by the engine and never reaches the script layer — a script cannot observe word size, endianness, or which platform it is running on, so there is no way to write one that only works on some of them.

The only thing that varies between deployments is which modules are present, and that is resolved at the load boundary.

### Resolve at compile/load time

Much of the heavy lifting of the language is translating user intent into concrete technicalities. This must be done as early as possible.

The load boundary is the last point at which this may happen. Any pruning or specialization the script layer relies on must be decidable there, before execution begins — nothing is deferred to run time to be sorted out later.

### Fail fast, keep the engine resilient

Errors halt script execution and return control to the host. A script must never bring down the entire game.

---

## Tooling

### Show the machinery in motion

The language and runtime make many decisions on the author's behalf. Tooling must show what those decisions were and how the result actually runs.

### Give visibility into performance and costs

Performance characteristics of the data and code are surfaced through tooling rather than written in source — hovering a declaration to see its size, analysis passes, warnings on oversized data.

A cost that can be neither stated as a language-level guarantee nor surfaced by tooling is a design smell, and the construct that carries it should be reconsidered.
