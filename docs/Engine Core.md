## Purpose

This document specifies the parts of the engine that constrain how data is laid out, scheduled, and synchronized. Subsystems that sit on top of the core are out of scope.

---

## Data Layout

### Component flattening

The layout of components is flattened, such that nested types become fixed offsets into the component's memory block.

Components are therefore transparent types to the engine: data at any nesting depth is addressed, change-tracked and access-analyzed the same way as top-level data.

---

## Storage Model

The concrete ECS storage model is undecided; see [Pending](Pending.md#storage-and-memory-layout).

"Memory block" means an ECS-managed data partition that holds components and auxiliary data.

### Constraints

Any storage model must satisfy these requirements:

- **Blind-copyability.** A memory block is transferable as an opaque byte range, with no per-pointer inspection or fixup at sync time.
- **Handle stability across mid-frame mutation.** Adding or removing a component on one entity does not invalidate a handle held to a different entity.
- **Partitioning follows ownership and serializability.** Ownership does not vary within a memory block, and a non-serialized component does not share a memory block with synced data.
- **Static addressability of fields.** A field resolves to an offset and a width, at any nesting depth.

---

## Memory Tiers

Three tiers, distinguished by who owns the storage and how long it lives:

- **Inline.** Stored directly in the component. Fixed size, known at declaration.
- **ECS-managed.** Stored outside the component but inside a managed memory block, with the component holding an offset. This is what `dynamic` selects.
- **General.** Ordinary script-side memory — locals, parameters, query bindings. Never reachable from a component.

### The flat-copyable rule

Everything reachable inside a component must survive being copied verbatim to another address space. An offset into engine-owned memory does; a raw pointer does not.

Eligibility is decided by taint propagation: a `dynamic` field taints the `value` containing it, and the taint propagates outward to disqualify any component holding it. Dynamic data is therefore permitted only at a component's top level.

Enums are flat-copyable by construction — an enum is laid out at the size of its largest variant plus its discriminant, so its size is fixed at declaration.

---

## Frame Model and Synchronization

State is synchronized between peers as per-frame chunk copies. A peer either owns entities or receives them.

---

## Scheduling and Execution

- **Access sets are inferred, never declared.** The compiler statically extracts per-field read/write sets from imperative bodies.
- **A system is an organization and scheduling construct, not a behaviour container.** A zero-argument block the engine instantiates and script never constructs.

---

## Not Yet Written

- Storage model, and the memory layout that follows from it — [Pending](Pending.md#storage-and-memory-layout).
- Entity identity and generation — [Pending](Pending.md#storage-and-memory-layout).
- Addressability of a `dynamic` component field — [Pending](Pending.md#storage-and-memory-layout).
- Storage for pointer-like component data (ECS-managed buffers) — [Pending](Pending.md#storage-and-memory-layout).
- Copy granularity and the synchronization path: memory block selection, delta compression, peer topology — [Pending](Pending.md#storage-and-memory-layout).
- Systems, dependency declaration and DAG construction — [Pending](Pending.md#systems-scheduling-and-parallelism).
- Whether `changed` fires on a non-owning peer — [Pending](Pending.md#events-and-change-detection).
- The host embedding API boundary — [Runtime & Deployment](Runtime%20&%20Deployment.md#not-yet-written).
