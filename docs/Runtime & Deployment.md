## Purpose

How Loom scripts are executed and shipped, as distinct from how they are compiled. Backend selection is a build-pipeline and platform concern, transparent to the script layer.

---

## Execution Backends

The compiler emits one `.wasm` artifact per module. The same artifact runs everywhere — the execution strategy is chosen at deploy time, per platform.

| Platform | Strategy | Notes |
| --- | --- | --- |
| Desktop | wasmtime or wasmer | JIT or interpreted, whichever the runtime prefers |
| Console | Cranelift AOT, or wasm3 / wasmi interpreter | JIT is forbidden by certification, so the choice is ahead-of-time native compilation or a pure interpreter |

## Why Wasm

- Sandboxing is structural: linear memory and no ambient authority make isolation a property of the execution model rather than of compiler correctness.
- Interop with Odin through mature runtimes is straightforward.
- Runtime performance improvements arrive from upstream.

## Hot Reload

Reload swaps a single module's Wasm object into the running instance, without a whole-program rebuild. Compiler-side requirements are specified in [Incremental compilation](Language%20Implementation.md#incremental-compilation).

## Not Yet Written

- Host embedding API: what the engine exposes to guest modules, and how capabilities are granted — [Pending](Pending.md#compilation-and-backend).
- Reload semantics for live state: what happens to entities and component data whose defining module is being swapped — [Pending](Pending.md#compilation-and-backend).
- Whether AOT and interpreted backends must agree observably — [Pending](Pending.md#compilation-and-backend).
- I/O surface: input, audio, asset loading, save files, network transport — [Pending](Pending.md#compilation-and-backend).
