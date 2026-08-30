# FAQ material

Worked-through explanations of decisions whose *rules* are already in the specs, kept in the shape an author would ask them rather than the shape a spec states them. Raw material for a user-facing FAQ; not authoritative, and not a place to record decisions. If something here contradicts the specs, the specs win and the entry is stale.

---

## Why does `//` floor?

`-7 // 2` is `-4`, not `-3`. C, C++, C#, Java, Rust and Odin all give `-3`, so this is a deliberate break with the languages most engine programmers arrive from.

**Floor and truncation only ever disagree on negative operands.** Sorting the real uses of `//` and `%` by whether their operands ever go negative:

| Never negative | Routinely negative |
| --- | --- |
| `count // stack_size` — items into stacks | `position // cell_size` — world position to grid or chunk coordinate |
| `seconds // 60` — time formatting | `position % cell_size` — offset within the cell |
| `i % 2`, `tick % 10 == 0` — parity, every-N-frames | `angle % 360` — wrapping a rotation, where `angle` came from `heading - delta` |
| `frame % frame_count` — looping animation | `(head - i) % capacity` — walking a ring buffer backwards |
| `(head + i) % capacity` — ring buffer forwards | |

In the left column the two rules give identical answers and nobody can tell which one is in effect. In the right column they differ, and floor is correct every time:

- Truncating `position // cell_size` makes cell `0` twice as wide as every other cell, because everything from `-0.9` to `0.9` maps to it.
- Truncating `angle % 360` returns a negative angle, which is not a wrapped rotation.

Both are classic bugs, and both live in spatial code — which is what this language is for.

**The expectation is real but narrow.** It comes from C, it is held by the engineer subset of the audience, and it predicts the wrong answer in every case where the operator's behaviour is actually observable. Authors coming from spreadsheets or from no programming background bring clock arithmetic instead, which floors.

**`%` is not a separate decision.** The identity `a == (a // b) * b + a % b` links the pair, so choosing one fixes the other:

- Truncate → the remainder takes the sign of the number being divided → `-1 % 360` is `-1` → wrapping needs a fixup at every call site.
- Floor → the remainder takes the *divisor's* sign → `-1 % 360` is `359` → wrapping just works.

This is also why the C family's `%` is a *remainder* rather than a modulo, and why `((a % b) + b) % b` appears in every C-family codebase that wraps an index. It reads as a language wart, but it is the unavoidable consequence of truncating division.

Python floors for exactly this reason, and the causality is the reverse of what the spelling suggests: Guido wanted `i % n` to land in `[0, n)` for positive `n`, and floor division is what that forces. Floor division was the consequence, not the goal.

**The cost falls the right way.** Hardware division truncates, so floor semantics cost a fixup — a sign test, a compare and two conditional adds, branchless. That fixup is compiled away whenever declared ranges prove both operands non-negative, which is the entire left column. It survives only in the right column, where the inferred interval straddles zero. So flooring is free where it makes no difference and costs a few instructions where it is the difference between correct and buggy.

## Why isn't `a // b` the same as `floor(a / b)`?

In Python it is, exactly. Here it isn't, and the reason is fixed point.

`/` keeps 17 fractional bits, so it can tell apart values about `0.0000076` apart — no closer.

Take `-2000001 / 1000000`. The exact answer is `-2.000001`: a millionth below `-2`, which is nearer to `-2` than `/` can represent. So `/` returns exactly `-2.0`, and `floor` has no way to know it should have gone lower. It returns `-2`, where the true floor of `-2.000001` is `-3`.

`//` returns `-3`, because it divides the two whole numbers directly and never builds the fraction that lost the information.

Only negative results are affected. The rounding moves a value toward zero, so a negative result can cross the whole number below it, while a positive one moves away from the boundary above and never crosses anything.

That narrows the trap without making it rarer: negative results are exactly what grid and chunk coordinates produce, which is the main thing `//` is for.

So the two are different operations rather than a spelling and its expansion, and `//` is the one to reach for whenever the whole-number result is the answer you want.

Python is exact here because its integers are arbitrary-precision, so it never has an unrepresentable intermediate to lose.

## Why is there no cast?

Because three different rounding behaviours are in play, and a cast-shaped syntax would silently pick one:

- Storing a value into a narrower precision **rounds to nearest**.
- `//` **floors**.
- A C-style cast, which is what the syntax would look like, **truncates** — and that is the one behaviour the language never performs.

So converting a `decimal` to an `integer` is written as the question being asked: `floor`, `round`, `ceil` or `truncate`. Rounding within a type stays implicit, because storing a wide expression into a declared field is how ordinary arithmetic terminates and requiring a wrapper there would make routine code unwriteable.

## Why is there no `Infinity` or `NaN`?

In Unity, Godot, or anything else built on floats, `x / 0` hands back `Infinity` and the frame keeps running. Here it halts.

**There is nowhere to put them.** Floating point can represent infinities and NaNs because IEEE 754 reserves a slice of the encoding for them — an exponent pattern that means "this is not a number". A fixed-point number has no reserved patterns; every bit pattern is a value. So the choice isn't between halting and returning `NaN`, it's between halting and returning a wrong number silently.

**And they are not wanted anyway.** A `NaN` propagates through every subsequent operation and surfaces somewhere far from where it was produced — a frozen animation, an entity teleported to nowhere, a physics body that vanished. The stack trace, when you finally get one, points at the victim rather than the cause. Halting at the division reports the actual problem.

Two things follow from their absence:

- **Comparison is total.** `a == a` is always true, and exactly one of `a < b`, `a == b`, `a > b` holds. Under IEEE semantics `NaN != NaN`, which quietly breaks sorting, deduplication and any cached comparison.
- **Peers cannot disagree.** State is synchronized between machines, and a value that is silently wrong is far worse there than one that halts — it desyncs the simulation instead of reporting itself.

The practical consequence is that a divisor which can be zero is something to handle rather than something to let ride. Declaring a range that excludes zero is the cheapest way to do that, since it also lets the compiler drop the check.

## Why does `1 / 3` not give `0`?

`/` always produces a full-precision result and narrows only where it is stored, so `1 / 3` is `0.333…` regardless of the operands being whole numbers. The operands' declared precision does not determine the result's.

The alternative — taking the result's precision from the operands, as SQL's `DECIMAL` does — gives `0` here, which is why SQL patches the rule with an arbitrary minimum digit count that its own implementations disagree on.

Fixed-point systems that face this choice honestly tend to refuse to make it: Ada's fixed-point division yields a type that is only legal where a target precision is supplied, and Java's `BigDecimal.divide` throws unless given an explicit scale. A fixed full-precision result reaches the same place without asking the author to state anything.

If you want the whole-number result, that is what `//` is for — and it is cheaper, since it skips the widening entirely.
