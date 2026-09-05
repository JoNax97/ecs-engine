## Purpose

This document specifies the parts of the engine that constrain how data is laid out, scheduled, and synchronized. Subsystems that sit on top of the core are out of scope.

---

## Data Layout

### Component flattening

The layout of components is flattened, such that nested types become fixed offsets relative to the component root.

Components are therefore transparent types to the engine: data at any nesting depth is addressed, change-tracked and access-analyzed the same way as top-level data.

---

## Entity identity

An entity has a stable ID, fixed for its lifetime, and a slot, which is its address in storage. Identity resolves to a slot through an engine-maintained mapping. Entity handles store an ID, never a slot. Migrating an entity between shards changes its slot and leaves its identity unchanged.

---
 
## Storage Model

Storage is an inverted hierarchical bitmap. Each component type owns a presence bitmap over entity slots and a data array indexed by slot. Adding or removing a component sets or clears a bit; entity data does not move because of structural changes.

### Constraints

Any storage model must satisfy these requirements:

- **Blind-copyability.** State is serializable and transferable as an opaque byte range, with no pointer chasing or per-entity churn.
- **Handle stability.** Adding or removing a component on an entity does not invalidate references to it.
- **Layout follows serialization.** Serialization decisions happen at a coarse memory level.
- **Static addressability.** Component-owned data resolves to a known offset and width, at any nesting depth.

### Component Shards

A Shard is an ECS-managed data region that holds components and their auxiliary data. Two attributes decide which shard an entity may occupy:

- **Ownership** — which peer holds authority over it.
- **Partition** — which spatial scope it belongs to. It's purposefully abstract; the engine attaches no meaning to them.

Therefore, a shard contains a range of data partitioned by `component id ✕ owner id ✕ partition id` and indexed by `entity slot`. Within a shard, entities are grouped automatically to improve locality. This grouping is automatic and not observable by scripts.

A component's auxiliary data lives in the same shard as the component that reaches it, and offsets into it are shard-relative.

---

## Memory Tiers

- **Local** Short-lived memory, stack-backed. Includes locals, parameters, query bindings, etc.
- **Managed** Engine-controlled data. Includes all component data.
- **Unmanaged** Ordinary script memory: file and module level variables.

Unmanaged memory is never synchronized and never serialized. State that has to cross a peer or survive a save belongs in managed memory.

### The flat-copyable rule

Everything reachable inside a component must survive being copied verbatim to another address space. An offset into engine-owned memory does; a raw pointer does not.

---

## Frame Model and Synchronization

State is synchronized between peers as per-frame shard copies. A peer either owns entities or receives them.
<<<<<<< HEAD
=======

Structural changes — component addition and removal, entity creation and destruction — take effect at the frame boundary, not at the point of the statement requesting them.
>>>>>>> b263ad3 (Initial ecs storage design)

---

## Scheduling and Execution

- **Access sets are inferred, never declared.** The compiler statically extracts per-field read/write sets from imperative bodies.
- **A system is an organization and scheduling construct, not a behaviour container.** A zero-argument block the engine instantiates and script never constructs.

