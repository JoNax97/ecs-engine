 # ECS Scripting Language
 
## 0. Scope
 
This document specifies the syntax and semantics of an ECS-native scripting language, inspired by SQL, Datalog and Rust. It is not meant to be a general-purpose programming language; all language constructs tie closely tied to the specific ECS architecture.
 
---
 
## 1. Program Structure
 
Code is organized using **files** and **modules**. A module is a collection of files located in the same directory, each beginning with the same module declaration:
 
```
module combat
```

A file can import code definitions from other modules by using the import keyword directly after the module declaration. Declarations can be marked as optional, in which case the compiler will enforce that all usages are properly guarded. 

```
import core_math
import optional cloth_physics
```

### Top-level statements
 
A file's top level is evaluated once at load time. The following statements are valid at the top level:
 
1. Symbol definitions via `define`.
2. Event listeners via `on <event>`.
3. Load-time resolvable `if`/`else` blocks.

An example of a valid top-level structure: 

```
module combat

import optional magic_items

define enum DamageType (
	Slashing,
	Blunt,
	Piercing,
	
	if magic_items
	   Magical
	end
)
```

## 2. Basic Syntax

The language aims to minimize the usage of punctuation marks and instead chooses to use plain English keywords wherever sensible. 

Blocks are opened with a keyword and closed with `end`.
Statements are newline-terminated with no semicolons.
Indentation is not significant; it's for readability only.

### Declaration and assignment
 
A single operator, `=`, is used for both declaring and reassigning a name.
The first use of a name in a scope declares it and fixes its type; every
subsequent use in that scope reassigns it. A name's type cannot change after
its first declaration.
 
```
integer y = 0   // explicit declaration
x = 5           // implicit declaration, type inferred
x = 6           // reassignment
```
 
### Operators
 
- Arithmetic:  `+ - * / %`
- Comparison:  `== != < <= > >=`
- Boolean: `and or not

### Comments
 
```
// line comment
/* block comment */
```
 
## 3. Control flow

### Conditional statements

The `if` statement evaluates a boolean expression and executes the corresponding code block. Multiple `if` statements can be chained together without needing to close each one with `end`.

```
if <condition>
    ...
else if <other condition>
    ...
else 
	...
end
```

 Conditional assignments can also be expressed using ternary expressions: 
 
 ```
 x = a if condition else b 
 ```

The `match` statement evaluates an expression against a set of patterns, running the block for the first match. 

```
match health
	when <= 0 
       print "dead"
    when <= 5
        print "healthy"
    else
        print "wounded"
end
```

### Loops

The `for` loop iterates over sequence of elements, like a numerical range or collection. 
 
``` 
for i in range(0..n)
    ...
end

for element in array
    ...
end
```

The `while` loop executes its body based on an arbitrary boolean expression.

```
while <condition>
    ...
end
```

### Assertions

Use the `assert` keyword to evaluate an expression and halt execution if it fails. Assertions can have an optional error message.

```
assert Health.Current <= Health.Max, "Health is over max allowed value"
```
 
---

## 4. Primitive Types

The `boolean` type is a boolean. What else do you want.
### Numeric Types

Numeric types are designed to allow for gradual refinement based on usage and performance needs. This means there are only 2 numeric types: `integer` and `decimal`.  Instead of manually encoding characteristics like width, signedness and precision into separate types, they are automatically determined based on constraints.

For integer types, storage width and signedness is inferred from its declared range. For example:

| Declaration                  | Width  | Signed |
| ---------------------------- | ------ | ------ |
| `integer health`             | 32-bit | yes    |
| `integer ammo range(0..999)` | 16-bit | no     |

The language uses fixed-point numbers to allow for fine-grained optimizations, while remaining simple to use for the common case.
For decimal types, storage width and signedness is inferred from both range and precision. For example:

| Declaration                                          | Width   | Signed | Precision |
| ---------------------------------------------------- | ------- | ------ | --------- |
| `decimal score`                                      | 32-bit  | yes    | 13 bits   |
| `decimal health range(0..1000)`                      | 24-bit  | no     | 13 bits   |
| `decimal position range(-10000..10000) precision(5)` | 32-bit  | yes    | 17 bits   |
| `decimal rotation range(0..360) precision(2)`        | 16-bits | no     | 7 bits    |
### Strings

Strings can be either fixed or variable in length. Fixed-length strings are inlined and can be used inside of components.

```
string name = "Loom"   // Variable-length string
string tag length(16)  // Fixed-length string
```

Strings can be interpolated by inserting arguments using `$`. Add parenthesis for more complex expressions:
 
```
"Score: $score"                          // bare, simple identifier 
"Damage: $(max(weapon.damage, 999))"     // parenthesized, arbitrary expression
```

### Arrays
 
An array is declared with a trailing bracket on the field name:
 
```
integer Slots[30]     // bounded, inline, no allocation
integer Slots[]       // unbounded, dynamically backed
```
 
### Ranges

`range(a..b)` denotes a bounded range; either end may be omitted to leave that side unbounded (`range(..n)`, `range(n..)`). The same `range(...)`  syntax is reused for loop iteration and for declaring numeric/cardinality bounds elsewhere in the language.

## 5. Data Modeling
 
 In this language, data and behavior are modeled directly as ECS primitives. All declarations in this section are introduced with `define` keyword. Many data types declare fields or arguments. These are declared in parentheses and are comma-separated,
 
### Values
 
A `value` is a plain aggregate type. It is copied on assignment and it's not directly addressable.  

```
define value Vector3 (
    integer x,
    integer y,
    integer z
)
```
  
### Components
 
A `component` is the unit of data an entity Components are query-able and independently addressable. 

```
define component Health (
    integer current,
    integer max
)
```
 
### Tags
 
A `tag` is a component with no data, only presence.

```
define tag Stunned
```
 
### Enums
 
An `enum` is a closed set of named labels. Each label may optionally carry a data payload.  Each label has a numeric value, defined explicitly or by declaration order. 
 
```
define enum Effect (
    Nothing,
    Stun,
    Heal(integer amount) = 10,    
)
```
 
Enums can be pattern-matched using `match` statements:

```
match action 
	when Stun
		apply_stun(target)
	when Heal(amount) 
		target.Health.current += amount
	when Nothing // no-op 
end
```

Enums can be added directly to entities, in which case they behave as an exclusive set of tags/components.
 
### Relationships
 
A `relationship` links entities. Relationships are special components with first-class syntax. 

By default, relationships are single target and unidirectional; only the source entity is aware of the relationship.

```
define relationship Target
```
 
Relationships can also have multiple targets. Max target amount is optional.

```
define relationship Targets[8]
```
 
Relationships can be barked as `mutual`.Mutual relationships are bidirectional; both sides are aware of each other. 
The same name can be used from both sides, or a different name can be specified for each side. Mutual relationships can also have multiple targets.

```
define relationship Spouse mutual
define relationship Parent, Children[10] mutual
```

 Relationships can also have data, just like normal components.
```
define relationship Likes (
    integer intensity
)
```
 
// TODO transitive and ephimeral, exclusive relationships
 
### Definition Visibility
 
Every `define` may be accompanied by a visibility keyword:
 
```
define private value HelperStruct(...)
```

| Keyword    | Scope                                              |
| ---------- | -------------------------------------------------- |
| `private`  | Visible only within the declaring file             |
| `internal` | Visible to any file sharing the same `module` name |
| `public`   | Visible to toher modules, via import               |

Defaults differ by category, following ECS principles:
- Data declarations (`value`, `component`, `tag`, `enum`,`relationship`) default to `public`. 
- Behavior and state declarations (`proc`, `var`, `query`) default to `private`.  
- No declarations default to `internal`; it must always be written explicitly.
 
---
 
## 6. Annotations
 
A declaration may be followed by one or more annotations to provide additional information about that declaration. An annotation is either a bare keyword or a keyword with parenthesized arguments, space-separated from the declaration and from each other. For example:
 
```
integer counter range(0..) // constraints the range to be non-negative
```
 
Annotations can be used with any declaration that can carry extra information; fields, arguments, queries, etc.

---
 
## 7. Procedures

Procedures are reusable code routines that can be invoked from anywhere: 
 
```
define proc lerp(a: number, b: number, t: number) returns number
    return a + (b - a) * t
end
```
 
Multiple return values are declared with a comma-separated, optionally named list after `returns`. The returned type is a tuple, whoch can be deconstructed at call site:
 
```
define proc divmod(a: number, b: number) returns number div number, number mod
    return a / b, a % b
end
 
q, r = divmod(10, 3)
```
 
There are no lambdas or closures. Procedures are named, free-standing, and referenced by name only.

---

## 8. Entities
 
`Entity` is a built-in handle type.
 
### Creation
 
```
e = create entity with
    Health(Current: 100, Max: 100),
    Position(Vec3(0, 0, 0)),
    Parent(other_entity)
```
 
Component construction requires named arguments when a component has more
than one field. A single positional argument is permitted only when a
component has exactly one field, or when constructing a designated built-in
value type (e.g. `Vec3(0, 0, 0)`).
 
### Access
 
```
h = e.Health  // halts if e does not have Health
if e has Health
    h = e.Health
end
```
 
### Destruction
 
```
delete e
```
 
---
 
## 9. Queries
 
A query declares a structural match over entities and, optionally, a body
that runs once per matching result.
 
```
define query nearby_enemies
    (attacker with Weapon, Position, Faction),
    (target with Health, Position, Faction)
where
    distance(attacker.Position, target.Position) <= attacker.Weapon.range and
    attacker.Faction != target.Faction and
    not target has Shield
do
    h = target.Health
    h.Current = h.Current - attacker.Weapon.damage
end
 
on tick nearby_enemies
```
 
### Bindings
 
Every name introduced in a `with` clause is always bound to an `Entity` —
there is no separate binding form for a component. Component data is
accessed from the bound entity using the dot syntax from §4
(`attacker.Weapon`).
 
A component listed in a `with` clause may carry a presence modifier:
 
```
(e with Position, optional Velocity)
(e with changed Health)
(e with Position, without Dead)
```
 
`without` excludes matches and binds no data.
 
### Clauses
 
- `with` — structural requirements (which components a binding must have).
- `where` — value predicates, combined with `and` / `or` / `not`.
- `do` — an ordinary imperative block, run once per match.
The split between `with`/`where` is an authoring convention for
readability; it does not constrain how the compiler evaluates or orders the
underlying conditions.
 
As a rule of thumb: a condition belongs in `with` when it can be resolved
to a fixed presence/bitmap check — structural component presence, tags,
relationship equality against a mutual relationship's indexed side, or an
enum comparison against a compile-time-resolvable set of labels (§3). A
condition belongs in `where` when it can only be evaluated per-entity at
runtime over an unbounded or continuous value (distances, arbitrary
numeric thresholds, comparisons against a value not known until runtime).
 
A bound relationship may be matched structurally by equality, provided the
relationship is `mutual` and the query binds from the side that holds the
index:
 
```
for (unit with Faction),
    (child with Parent = unit)
do
    child.Faction = unit.Faction
end
```
 
Matching in the opposite direction (checking a unidirectional relationship
against a specific runtime target) has no equivalent index and is a
per-entity runtime check like any other `where` predicate.
 
`do ... end` may be omitted when the body is exactly one statement that
begins with a keyword:
 
```
(h with Health)
delete h
```
 
A query with an empty body has no effect and is compiled out.
 
### Reductions
 
A `for`/`where` clause followed by a reducer, instead of a `do` block,
becomes a single-value expression usable anywhere a value is expected:
 
```
target = for (sub with Faction, Rank)
    where sub.Faction == unit.Faction and sub.Rank == unit.Rank - 1
    max_by sub.Victories
```
 
`count` and structural/relationship-cardinality reductions resolve from
existing presence bitmaps and relationship counters at no additional scan
cost. `sum`/`avg` over a field, and `max_by`/`min_by`, require visiting
every matching entity and cost the same as an equivalent hand-written
scan — the language does not disguise this cost as free.
 
There is no general materialized or orderable result-set type. Grouping,
sorting, and top-N selection are intentionally outside the query language;
where needed, they are written as ordinary iteration inside a `proc`.
 
### Declaring and triggering
 
There are four forms:
 
**Named, self-driving** — declared once, bound to a trigger separately:
```
define query nearby_enemies (...) where ... do ... end
on tick nearby_enemies
```
 
**Named, manual** — declared but never bound to a trigger; invoked directly
by name from inside a procedure or another query's body.
```
define query nearby_enemies (...) where ... do ... end
```
 
**Anonymous, self-driving** — declared and bound in a single statement; not
addressable, always file-private:
```
on tick
for (attacker with Weapon, Position, Faction), (target with Health, Position, Faction)
where ...
do
    ...
end
```
 
**Anonymous procedure trigger** — no structural match at all, just code
that should run on an event:
```
on tick do
    ...
end
```
 
`on <event> <name>` accepts either a named query or a named procedure —
both are valid trigger targets.
 
---
 
## 10. Events
 
Built-in triggers established in this specification:
 
- `tick` — fires every frame.
- `changed(Component)` — fires on the frame a matching component's value
  changes.
- `load` — fires once, at world/level load.
`on` is the sole binding statement for triggers, used as shown throughout
§6 and §7.
 
---
 
## 11. Not Yet Specified
 
The following areas are known to be part of the language but have not been
resolved in this specification:
 
- Memory tiers, handle-validity states, and null/absence semantics
  (carried over from an earlier design layer, not yet reconciled with the
  constructs above).

- Generics and trait/conformance syntax.

- Storage location for payload data on symmetric or many-to-many
  relationships, which have no single owning side.

- Declaration syntax for custom, game-level events (e.g. `player_joined`)
  beyond the built-in `tick` / `changed` / `load` triggers. Binding a
  parameterized event to a query/proc without the trigger's parameter
  colliding with a `with`-bound name (e.g. `on dead(unit)` alongside a
  `with`-bound `unit`) is parked pending this.

- Quantified negation over a relationship or sub-match ("no entity related
  to this one satisfies X") — identified as a real gap, no syntax chosen.

- Syntax for direct iteration over a bound relationship's targets outside
  a query (e.g. given a held `Entity`, iterating its `Children`) — sketched
  as reusing the existing `for ... in` loop form, not finalized.

- Whether `sum`/`count` reductions over a live query can be maintained
  incrementally (updated on write rather than rescanned on read) — would
  require exposing the prior value on a `changed` event, which is not yet
  designed.
