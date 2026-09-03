# Loom

Loom is an ECS engine and runtime. LoomScript is its scripting language, conceived as genuinely domain-native in the way SQL is native to relational databases: ECS primitives — entities, components, systems, queries, relationships — are the grammar itself, not an API layer over a general-purpose language.

Nothing is implemented; active work is iterative spec-writing. Solo project — no README, onboarding docs, or collaboration scaffolding are wanted.

## Documents

`docs/` is split on a **contract/mechanism seam**.

- [Design Principles](docs/Design%20Principles.md) — the criterion the specs are judged against.
- [Language Spec](docs/Language%20Spec.md) — contract: what an author may rely on.
- [Language Implementation](docs/Language%20Implementation.md) — mechanism: how the contract is delivered.
- [Engine Core](docs/Engine%20Core.md) — engine-side contract.
- [Engine API](docs/Engine%20API.md) — API surface; very early.
- [Pending](docs/Pending.md) — the queue of unresolved items.
- [Shelved](docs/Shelved.md) — options decided against and accepted holes.
- [Runtime & Deployment](docs/Runtime%20&%20Deployment.md) — execution and hot-reloading. Not a language concern.
- [LoomScript Examples](docs/LoomScript%20Examples.md).
- [Previous Iteration](docs/Previous%20Iteration.md), [Previous Iteration Syntax](docs/Previous%20Iteration%20Syntax.md) — superseded design. Readonly and non-authoritative.

`.claude/internal-clauses.md` holds the dependency edges behind the decisions — what a rule is load-bearing for, and what breaks if it is reversed. Agent-managed, not part of the spec set. Its own header states its format and citation rules. Never read it end to end; query it with `python3 scripts/clause.py <pattern>` (matches heading, citation, or body of a decision). A doc edit already owed but blocked on an unmade decision is recorded as an `Owed edit:` bullet inside the entry it concerns and listed in the file's own header — check that list before touching an affected section, and never silently "fix" an inconsistency one names.

## General work rules

**Revisit prior verdicts as decisions accumulate** Design decisions interact; a verdict reached early can be invalidated by a later one, and treating past conclusions as settled produces an incoherent spec. When a new decision touches an earlier one, say so and reopen it rather than letting the contradiction sit.

**Work one question at a time**, reasoning through implications before committing.

**Distinguish "closed" from "escalated to a tracked decision"**: Never leave a gap silently.

## What goes where

Every doc in `docs/` states settled decisions only. Four destinations, applied on every doc edit:

- **A decision** → the relevant spec doc, stated as a rule with no justification tail.
- **Anything undecided, speculative, or "TBD"** → `Pending.md`, categorized and importance-rated.
- **Rejections, and accepted gaps** → `Shelved.md`, with a revisit condition if needed.
- **Internal reasoning** — "x is needed for y", "this depends on z", "reversing this breaks w" → `.claude/internal-clauses.md`. Only for AI reference. Update at the same time as other docs.

## Writing the spec

**Keep the right level of precision.** The minimum precision that constitutes a guarantee, without getting trapped in the details. State results and costs plainly without the mechanism that produces them.

**Watch for the three-way leak.** Do not mix rules with (a) the reasoning behind it, (b) a restatement of a design principle, and (c) a forward-looking note belonging in Pending. Write the rule, then sort every following sentence into its bucket.

**Do not state or exemplify what is trivially derivable.** A consequence that follows directly from an existing rule needs no sentence and no example. Restating a general rule inside a specific section is the same error.

**Keep [LoomScript Examples](docs/LoomScript%20Examples.md) in sync.** Where the two disagree, the spec wins and the example changes; where the spec has no position, leave the example and track the divergence.

## Writing Pending entries

`Pending.md` holds **enough to pick up a work item, and nothing more**. It is not a record of every argument that produced it. Write notes, not prose:

- **Open items are questions.**
- **One question per bullet.**
- **Fragments are fine, avoid connective tissue.**
- **Link the spec, do not restate it.**
- **No prior art unless it *is* the argument.**
- **Keep it short: median ~100 words, max ~300.**

## Checking your work

- When asked for a final check, a proofread, a review before submitting, etc, run `python3 scripts/lint-links.py` **first**, and report its result before any other finding. It checks for invalid and stale links. Exit status is 1 if anything is wrong.
