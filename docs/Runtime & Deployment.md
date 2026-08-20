## Purpose

How Loom scripts are executed and shipped, as distinct from how they are compiled. Backend selection is a build-pipeline and platform concern, transparent to the script layer.

---

## Execution Backends

The compiler emits one `.wasm` artifact per module. The same artifact runs everywhere — the execution strategy is chosen at deploy time, per platform.

| Platform | Strategy | Notes |
| --- | --- | --- |
| Desktop | wasmtime or wasmer | JIT or interpreted, whichever the runtime prefers |
| Console | Cranelift AOT, or wasm3 / wasmi interpreter | JIT is forbidden by certification, so the choice is ahead-of-time native compilation or a pure interpreter |

Console portability is not blocked by Wasm as such. The actual constraint is JIT, and both AOT compilation and interpretation sidestep it while keeping the script binary identical across platforms.

## Why Wasm

- Sandboxing is **structural** rather than policy-enforced: linear memory and no ambient authority mean isolation is a property of the execution model, not of correctness in a compiler we maintain.
- Wasm interop with Odin through mature runtimes is straightforward.
- Runtime performance improvements arrive from upstream.

## Hot Reload

Reload swaps a single module's Wasm object into the running instance, without a whole-program rebuild. The compiler-side requirements — per-module objects and linkage that survives recompiling one module in isolation — are in the [implementation spec](Language%20Implementation.md).

## Not Yet Written

- Host embedding API: what the engine exposes to guest modules, and how capabilities are granted.
- Reload semantics for live state — what happens to entities and component data whose defining module is being swapped.
- Whether AOT and interpreted backends must agree observably (execution bounds, numeric edge cases), or may differ.
- I/O surface: input, audio, asset loading, save files, network transport. Not excluded by the design, simply not yet specified as host-exposed capabilities.
