## Scope
 
This document specifies the syntax and features of **LoomScript**, an ECS-native scripting language designed for the **Loom game engine**, inspired by SQL, Datalog and Rust.

LoomScript's constructs are closely tied to the ECS architecture. It is not meant to be a general-purpose programming language.

## Non-goals

The following are absent by design, not features awaiting implementation.

- **No garbage collector.** The runtime owns memory. Components live in ECS storage and locals live on the stack; nothing an author writes allocates.
- **No manual memory management.** No pointers, no allocate and free, no ownership annotations.
- **No inheritance and no subtyping.** Composition is the ECS itself. Shared behaviour is procedure overloading.
- **No closures, lambdas, or first-class functions.** Procedures are named and resolved at compile time, and are passed only through a [signature](#signatures).
- **No reflection.** Type and field information is not available to a running script.
- **No dynamic typing and no universal type.** Every value's type and layout are known at compile time.
- **No asynchronous execution.** Nothing suspends a body mid-frame. An operation that spans frames is observed on a later frame, never awaited.

---
 
## Basic Syntax

The language aims to minimize the usage of punctuation marks and instead chooses to use plain English keywords wherever sensible. Blocks are opened with a keyword and closed with `end`. Indentation is not significant; it's for readability only.

Parentheses are used to group elements. Wherever a construct reads unambiguously without them, they may be dropped, and the parentheses-less form is considered idiomatic. The conditions for dropping are stated case-by-case.

Identifiers may be written unqualified wherever the context determines what they refer to. The qualified form is always valid.

Comments are single line and start with a pipe character `|`. Comments have no closing character, and run to the end of the line.

```
| this is a comment
```

### Statements and Expressions

A statement is a construct that performs an action. Statements are newline-terminated with no semicolons, and form the body of every block. Statements are standalone and cannot be used as operands.

An expression is a construct that produces a value. Expressions must always be part of a statement or another expression; they cannot be standalone.

Procedure calls can be both. Procedures without side effects (also known as 'pure functions') cannot be used as statements; their result must be used, or explicitly discarded with `_ =`.

```
| Valid
damage = weapon.base * multiplier      | Multiplication expression, part of an assignment statement
apply_damage(target, damage)           | Procedure with side effects, valid as a standalone statement
_ = lerp(a, b, 0.5)                    | Pure procedure, part of a discard statement

| Invalid
weapon.base * multiplier               | Multiplication expression cannot stand alone
e.Health                               | Field access expression cannot stand alone
lerp(a, b, 0.5)                        | Pure procedure with result unused
```

### Identifiers

Identifiers in LoomScript can contain ASCII letters, numbers and underscores, and must start with a letter. Unicode characters are not valid in identifiers.
Identifiers must be unique within their scope. Keywords are reserved and cannot be used as identifiers.

By convention, type identifiers are written in `PascalCase`; everything else in `snake_case`.
 
Component access on an entity keeps the type's casing, because it names a type rather than a field:
 
```
e.Health.current  | Health is a type, not a field
```

### Variables
 
A variable is an identifier whose value can change. It is declared with a type and assigned with `=`.

Variable types are static: fixed at declaration and unable to change. Declarations begin with the type followed by an identifier, may carry [annotations](#annotations), and may omit the initializer.

```
integer health                   | zero-initialized
integer ammo range(0..999) = 30  | explicit value, annotated
```

Inside procs and query bodies, variable declarations can be inferred by using the `let` keyword followed by an identifier. `let` infers the type from its initializer and therefore always requires one. `let` takes no annotations. A `let` declaration assumes the most generous representation available, so it can hold any value a declared field can produce. To control representation, use explicit declaration.

A bare assignment using `=` reassigns a previously declared variable. Assigning an undeclared variable is an error.

```
let x = 5                        | inferred
x = 6                            | reassignment
```

### Bindings

A binding is an identifier whose value is supplied by the construct that introduces it: procedure parameters, loop variables, entities in a query, and casted values.

A binding cannot be reassigned, but it can be mutated if the underlying type allows it. To derive a new value from a parameter, declare one.

```
define proc apply_damage(Health health, integer amount)
    amount = clamp(amount, 0, health.current)        | Invalid, amount cannot be reassigned
    let dealt = clamp(amount, 0, health.current)     | Do this instead
    health.current -= dealt                          | Valid, health is mutated, not reassigned
end
```

### Constants

A constant is an identifier whose value is fixed before the program runs. It is assigned once, from an expression composed of literals and other constants in scope, and is never reassigned.

A `const` may appear at the top level or inside any block. Constants cannot be given a type or annotations.

```
const max_inventory = 30

integer slots[max_inventory]
```

### Discards

A bare `_` marks a value that is not needed: a discarded return value, an unused parameter, an unused loop variable. It may be repeated within a scope. Some constructs  allow the identifier to be omitted entirely, in which case the discard is not needed.

```
let div, _ = divmod(10, 3)
```

### Operators
 
Mathematical operators define addition ` + `, subtraction ` - `, multiplication ` * `, division ` / ` and remainder ` % `  
They can be compounded with assignment:

```
x += y
n *= t
```
There are no unary increment/decrement operators (` ++ -- `).

Comparison operators define equality ` == `, inequality ` != `, and arithmetic comparisons ` < <= > >= `

- Boolean: `and`, `or`, `not`
- Presence: `has`, `has no`, `has not`
- Narrowing: `is`, `is not`
- Membership: `in`, `not in`

The negated forms are single operators, different from `not` applied to a result, and are considered idiomatic. Nothing can be bound by a negated form. `has no` and `has not` are the same operator, with a small spelling concession for legibility.

## Control flow

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
        print "wounded"
    else
        print "healthy"
end
```

### Loops

The `for` loop iterates over a sequence of elements, like a numerical range or collection. 
 
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

### Error Handling

Use the `fail` keyword to halt script execution. An optional message can be included. 

```
if health.current > health.max
	fail "Health is over max allowed value"
end
```

Use the `assert` keyword to evaluate an expression and halt script execution if it fails. The following code is equivalent to the one above:

```
assert(health.current <= health.max, "Health is over max allowed value")
```
 
---

## Primitive Types

The `boolean` type is a boolean. What else do you want.

### Numeric Types

There are only two numeric types: `integer` and `decimal`. Width, signedness and precision are not encoded into separate types; they are derived from the declared constraints, so a declaration can be refined by adding an annotation rather than by changing its type.

For integer types, storage width and signedness is inferred from its declared range. For example:

| Declaration                  | Width  | Signed |
| ---------------------------- | ------ | ------ |
| `integer health`             | 32-bit | yes    |
| `integer ammo range(0..999)` | 16-bit | no     |

The language uses fixed-point numbers to allow for fine-grained optimizations, while remaining simple to use for the common case.
For decimal types, storage width and signedness is inferred from both range and precision.

`precision(n)` is declared in **decimal places**, and accepts `n` up to 5. The Precision column below reports the resulting fractional width.

Storage widths are a guarantee, not an optimizer preference: a declaration that resolves to 16 bits will always be 16 bits, and may be budgeted against — for memory, and for the bandwidth it costs to synchronize. How widths are derived is in the implementation spec.

| Declaration                                          | Width   | Signed | Fractional width |
| ---------------------------------------------------- | ------- | ------ | ---------------- |
| `decimal score`                                      | 32-bit  | yes    | 13 bits          |
| `decimal health range(0..1000)`                      | 24-bit  | no     | 13 bits          |
| `decimal position range(-10000..10000) precision(5)` | 32-bit  | yes    | 17 bits          |
| `decimal rotation range(0..360) precision(2)`        | 16-bit  | no     | 7 bits           |

### Strings

Strings can be either fixed or variable in length. Fixed-length strings are inlined and can be used inside of components.

```
string name = "Loom"   | Variable-length string
string tag length(16)  | Fixed-length string
```

Inside a `define`d type, a `string` must state its storage: either a `length(n)`, or `dynamic`. See [Storage](#storage).

Strings can be interpolated by inserting arguments using `$`. Add parenthesis for more complex expressions:
 
```
"Score: $score"                         | bare, simple identifier 
"Damage: $(max(weapon.damage, 999))"    | parenthesized, arbitrary expression
```

### Arrays
 
An array is declared with a trailing bracket on the field name:
 
```
integer slots[30]    | bounded, inline, no allocation
integer slots[]      | unbounded, dynamically backed
```

Inside a `define`d type, an array must state its storage: either a bound, or `dynamic`. See [Storage](#storage).

An array literal is a bracketed, comma-separated list of values of a single type. Its bound is the number of elements written.

```
let scores = [10, 20, 30]    | integer[3]
```

### Tuples

A tuple is a fixed group of up to four elements of differing types. A tuple type is written as a parenthesized parameter list. Elements take no annotations, and a tuple takes the representation its initializer produces.

Tuple elements are either all named or all unnamed; the twoe cannot mixed. Unnamed elements are accessed by ordinal names: `first`, `second`, `third`, `fourth`.

```
let pair = (x, y)
let result = (min: n, max: m, avg: q)

print pair.first
print result.min
```

Tuples are stack-only: a tuple cannot be a field of a `define`d type. It cannot be indexed or iterated.
Tuples are compared structurally: Two tuples are compatible when their element types and order match. Element names are not considered.

A tuple is constructed implicitly when an argument list is passed to a tuple parameter, and is never taken apart implicitly. Implicit construction is a coercion, so an exact parameter match is preferred over it.

```
define proc translate(Entity e, (integer x, integer y) delta) 
...
end

translate(e, 1, 2)      | builds the tuple
translate(e, delta)     | passes an existing one
```

Deconstruction is explicit, written as a comma-separated list of targets on the left of a `let` or an assignment.

```
let div, mod = divmod(10, 3)
a, b = b, a
```

Procedures with [Multiple return values](#procedures) produce tuples.

### Ranges

`range(a..b)` denotes a bounded range; either end may be omitted to leave that side unbounded (`range(..n)`, `range(n..)`). The same `range(...)`  syntax is reused for loop iteration and for declaring numeric/cardinality bounds elsewhere in the language.

A range constraining a numeric type must include zero. Data is always zero-initialized, so a range that excluded it would declare its own starting value impossible. `range(-10..100)` is fine; `range(1..999)` is not, and costs nothing to widen, since both spellings resolve to the same storage width.

The `in` operator tests membership, and takes a range as its right operand.

```
if damage in range(0..100)
    ...
end

when in range(0..5)   | as a match arm
```

A declared range narrows storage but does not bound it exactly — `range(-10..100)` resolves to a signed byte, which can hold -128. Writing a value outside the declared range fails. Values never wrap; use `%` where wrapping is the intent. Clamping is available but requires explicit syntax, so it is never what happens by accident.

## Program Structure
 
Code is organized using **files** and **modules**. A module is a collection of files located in the same directory, each beginning with the same module declaration:
 
```
module combat
```

A file can import code definitions from other modules by using the import keyword directly after the module declaration. Declarations can be marked as optional, in which case the compiler will enforce that all usages are properly guarded. 

```
import core_math
import optional cloth_physics
```

### Events

Events are the main way by which scripts hook into the running game. There are no specially named procedures that the runtime calls automatically. Instead, the engine exposes a series of built-in events that scripts can listen to. For example:

- `load` — fires once, at world/level load.
- `tick` — fires every frame.

Use the `on` keyword to listen to events. Both procedures and queries can be hooked up to events. Anonymous blocks can also be declared as listeners.

Listeners are attached statically. Every listener is declared at the top level and is resolved by the load boundary; a listener cannot be registered, replaced or removed while the game runs. A listener that should not act is expressed by matching nothing, or pruned entirely by a [load-time conditional](#load-time-conditionals) — not by unsubscribing.

```
on load do
 ...  | initialization
end

on tick update_velocity
```

### Load-time conditionals

A load-time conditional is any `if` statement whose condition can be resolved when loading the module. Ternary operators can also be load-time conditionals.
Module names can be used as constants to check if that module is present at load time. 

```
const hair_subdivisions = 10 if cloth_physics else 1

if cloth_physics
  <declarations and statements>
else
  <fallback>
end
```

Load-time conditionals can appear inside imperative blocks just like normal `if` statements, or they can be used to wrap entire declarations (see next section).

Partial symbol definition (putting fields, arguments, etc under conditionals) is not allowed. Symbol redefinition (defining 2 different things under the same name) is not allowed either, even if the conditionals are mutually exclusive.

All conditional branches are resolved and checked before any is stripped, so the compiled code must remain valid under all of them. Stripping itself is an optimization, not a guarantee.

> [!NOTE]
> Constants that depend on a load-time conditional cannot be used to determine data layout: array bounds, range constraints, etc.

### Top-level statements
 
A file's top level is evaluated once at load time. The following statements are valid at the top level:
 
1. Type definitions
2. Constant and variable declarations
3. Event listeners
4. Load-time conditionals

An example of a valid top-level structure: 

```
module combat

import optional magic_items

define enum DamageType (
	Slashing,
	Blunt,
	Piercing
)

if magic_items
	define tag Enchanted
end
```

## Data Modeling
 
In this language, data and behavior are modeled directly as ECS primitives. All declarations in this section are introduced with the `define` keyword. 

Many data types declare fields or arguments. These are declared in parentheses and are comma-separated. 
  
Fields cannot declare default values, and are always zero-initialized. 

Every type is either a value or a handle, and that decides what an identifier naming it does.

- A **value** is copied on assignment. Two identifiers never name the same value, and writing through one cannot be observed through another.
- A **handle** refers to data the runtime owns. Entities and components are handles. Assignment copies the handle, not the data, so two identifiers may name the same data and a write through either is visible through both.

Handle data is not addressable outside the frame it is used in. A handle may not be stored in a component, in file state, or held across a frame boundary, so a handle can never refer to data that no longer exists.
 
### Values
 
A `value` is a plain aggregate type. It is copied on assignment and is not directly addressable.  

```
define value Vector3 (
    integer x,
    integer y,
    integer z
)
```
  
### Components
 
A `component` is the unit of data an entity. Components are query-able and independently addressable. 

```
define component Health (
    integer current,
    integer max
)
```
 
### Tags
 
A `tag` is a special kind of component with no data, only presence.

```
define tag Stunned
```
 
### Enums
 
An `enum` is a closed set of named labels. Labels optionally may have one more fields.
Each label also has numeric value derived from its declared order. The first label is the default one and always equals zero.

```
define enum Effect (
    Nothing,
    Stun,
    Heal(integer amount range(0..1000), Entity source)
)
```

Enums can be pattern-matched using `match` statements. A label's fields are accessed by binding the label to an identifier:

```
match effect 
	when Stun
		apply_stun(target)
		
	when Heal heal
		target.Health.current += heal.amount
		
	when Nothing  | no-op 
end
```

The `is` operator can also be used to test a label and bind it to an identifier.

```
if effect is Stun   | no payload to bind
    apply_stun(target)
end

if effect is Heal heal
    heal.amount = min(heal.amount, remaining)
    target.Health.current += heal.amount
end
```

Enums can be added directly to entities, in which case they behave as an exclusive set of tags/components. Presence is tested with `has`, and the label with `is`.

```
if e has Effect              | the entity has any effect
if e has Effect.Stun         | the entity has the stun effect
if e.Effect is Heal heal     | errors if the entity has no effect
```
 
### Relationships
 
A `relationship` is a special kind of component that links entities together.

By default, relationships are single target and unidirectional; only the source entity is aware of the relationship.

```
define relationship Target
```
 
Relationships can also have multiple targets. Max target amount is optional.

```
define relationship Targets[8]
```
 
Relationships can be marked as `mutual`. Mutual relationships are bidirectional; both sides are aware of each other. 
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
 
Transitive, ephemeral and exclusive relationships are unspecified; see [Pending](Pending.md#relationships).

### Visibility
 
Every `define` may be accompanied by a visibility keyword:
 
```
define private value HelperStruct(...)
```

| Keyword    | Scope                                              |
| ---------- | -------------------------------------------------- |
| `private`  | Visible only within the declaring file             |
| `internal` | Visible to any file sharing the same `module` name |
| `public`   | Visible to other modules, via import               |

Defaults differ by category, following ECS principles:
- Data declarations (values, components, enums, etc) default to `public`. 
- Behavior and state declarations (procedures, variables, queries) default to `private`.  
- No declarations default to `internal`. 

### Storage
 
Fields inside defined types are inlined by default. Most types have a fixed size so this is not an issue. However, for types that might have a dynamic size, like strings and arrays, the user must specify a fixed size or explicitly mark them as `dynamic`.

`dynamic` opts a field out of inline storage. The field's storage is then managed by the runtime and the field holds a reference to it. This is transparent for the user but must be spelled out because it's more costly than the inline form.

```
define value Label (
    string text length(32),    | inline
    string body dynamic        | separately stored, costlier
)
```

 > [!IMPORTANT]
 > Dynamic data is allowed only at a component top level. A `value` with a `dynamic` field cannot be used inside a component; hoist the field to the component itself.

Proc arguments and variables declared outside of defined types are not inlined by default. A bare string or array is dynamically backed and no annotation is needed.

```
string text  | Dynamically sized by default

define proc sum(integer[] numbers)  | Argument can receive both dynamic and fixed arrays
    ...
end
```

### Construction

Types are constructed simply by using the type identifier. There is no `new` operator. 

Field values can be passed positionally or by name. Named values must always be passed after positional ones.
Parens are optional when no values are assigned.  Values not passed are initialized with their zero values. 
 
```
let v = Vector3 | Same as to Vector3()

v = Vector3(1, 2, 3)

let w = Weapon(damage: 10, ammo: 100)

let l = Label(text, size, alignment: Alignment.Left)
```

---
 
## Annotations
 
A declaration may be followed by one or more annotations to provide additional information about that declaration. An annotation is either a bare keyword or a keyword with parenthesized arguments, space-separated from the declaration and from each other. For example:
 
```
integer counter range(0..) | constrains the range to be non-negative
```
 
Annotations can be used with any declaration that can carry extra information; fields, arguments, queries, etc.

---
 
## Procedures

Procedures are reusable code routines that can be invoked from anywhere:
 
```
define proc lerp(decimal a, decimal b, decimal t) returns decimal
    return a + (b - a) * t
end

| usage
let f = lerp(a, b, 0.5)
```
 
Multiple return values are declared with a comma-separated, optionally named list after `returns`. The returned type is a tuple, which can be deconstructed at call site:
 
```
define proc divmod(integer a, integer b) returns integer div, integer mod
    return a / b, a % b
end

| usage
let div, mod = divmod(10, 3)
```

Parentheses at the call site are for grouping arguments. They may be omitted when the call is a statement and passes zero or one argument. A paren-less argument extends to the end of the statement and is parsed as a single expression. 

In argument position, a bare procedure name is a reference to the procedure itself.

```
| Valid
test_and_halt        | zero-argument call as a statement
print 10 + 5         | equivalent to print(10 + 5)
print get_score()    | the argument is a call expression
print pow2(100)      | statement witout parens, expression with parens

| Invalid
print(pow2 100)      | inner call is nested, needs its own parens
print get_score      | a bare name in argument position is a reference; print exptects a value
```

> [!TIP]
> There are no lambdas or closures in LoomScript. Procedures are statically resolved, free-standing, and referenced by name only. 

### Procedure Overloading

Procedures may be overloaded, giving one operation a single name across the inputs it accepts. Overloaded procedures share an identifier, and accept different types and/or amounts of arguments. Procedures' return types, parameter names and constraints are not considered for overloading.

```
define proc damage(Entity target, integer amount) ...

define proc damage(Entity target, decimal fraction) ...

define proc damage(Entity target, integer amount, DamageType kind) ...
```

When calling an overloaded procedure, the one requiring the least coercion is selected.

```
define proc foo(integer a, integer b) ...

define proc foo(integer a, decimal b) ...

foo(2, 3)  | Chooses the first declaration since it better matches the arguments
```

### Signatures

A signature declares a named parameter list and return type, so that a procedure can be passed to another procedure.

```
define signature ItemComparison(Item a, Item b) returns boolean

define proc sort(Item items[], ItemComparison before)
    ...
end

define proc by_weight(Item a, Item b) returns boolean
    return a.weight < b.weight
end

| usage
sort(inventory, by_weight)
```

The argument must be a named procedure or a parameter of a matching signature, resolvable at compile time. If the proedure is overloaded, the least-coercion rule applies. Parameter names in a signature are documentation only; matching is by type and order.

Signatures may only be used as parameter types. Procedures cannot be stored; therefore a signature cannot be the type of a variable, field, variable, or return value.

---

## Entities
 
`Entity` is a built-in handle type.

All entities have a unique numeric ID.

```
print entity.id
```
 
### Creation
 
```
let e = create Entity with 
    Health(current: 100, max: 100),
    Position,
    Parent(other_entity)
```

The `with` list may be wrapped in parentheses, but the form above is idiomatic. A component taking no arguments drops its empty parentheses, so `Position` and `Position()` are the same.
 
### Component Access

Components of an entity can be accessed directly by using the component Type as if it was a field. Because it is not possible to know beforehand if an entity has a certain component, this access can fail.

To check that a component is present before accessing it, use the `has` operator.
 
```
let h = e.Health  | fails if e does not have Health

if e has Health
    print e.Health
end

if e has no Shield
    apply_damage(e, amount)
end
```

`has` can also bind the component to an identifier for safe and direct use.

```
if e has Health health
    health.current -= 10
end
```

Both forms stay available: a bare `has` followed by ordinary component access is unchanged, and remains fallible.

### Change Tracking

`changed(Component)` fires on the frame a matching component's value changes.

The rest of the change-tracking surface is unwritten; see [Pending](Pending.md#events-and-change-detection).
 
### Destruction
 
```
delete e
```
 
---
 
## Queries
 
A query declares a structural match over one or more entities, an optional set of conditions to filter them, and a body that runs once per matching result. Like procs, queries can be named if they want to be manually invoked, or they can remain anonymous and be declared directly as event listeners.
 
```
define query attack_nearby_enemies
for
    (attacker with Weapon, Position, Faction),
    (target with Health, Position, Faction)
where
    distance(attacker.Position, target.Position) <= attacker.Weapon.range and
    attacker.Faction != target.Faction and 
    not target has Shield
do
    let h = target.Health
    h.current = h.current - attacker.Weapon.damage
end
```

### Clauses

Queries are comprised of the following clauses:
 
- `for` — structural requirements (which components a binding must have).
- `where` — value predicates, combined with `and`/ `or` / `not`.
- `do` — imperative block, run once per match.

As a rule of thumb: a condition belongs in `for` when it involves matching components structurally, or comparing against a bounded set of values.

A condition belongs in `where` when it involves comparing a component's fields against unbounded or continuous values (distances, arbitrary numeric thresholds, etc).

### The `for` clause

The for clause expresses a list of entities to be bound and iterated. Every identifier introduced in a `for` clause is always bound to an `Entity`. Entity bindings cannot be discarded using `_`.

The simplest `for` clause matches all entities:

```
for entity  | entity is bound and can be used inside query bodies
do
  print entity.id
end
```

Components cannot be bound by name. Component data is accessed from the bound entity using the syntax from [Component Access](#component-access).
 
Components listed in `for` clause require a presence modifier. A single modifier can apply to multiple, comma separated components.

`with` matches entities that have the specified component.
`without` matches entities that don't have the specified component.
`with changed` matches components that have changed in the last tick.

```
e with Position, Velocity

e with changed Health

e without Dead
```

Parentheses separate one binding from the next, so a `for` clause matching a single entity may omit them.

Relationships can be matched structurally to check for specific targets. The targets can be an externally supplied entity or an entity bound within the query.
 
```
for (unit with Faction), (child with Parent unit)
do
    child.Faction = unit.Faction
end
```

### The `do` clause

The `do` clause is the last part of the query (also known as the body). It's an imperative block where all bound entities can be used to execute arbitrary logic. It is the only part of the query where data may be modified.

```
for entity with Position, Velocity
do
  entity.Position.value += entity.Velocity.value
end
```
  
The `do ... end` keywords may be omitted when the body is exactly one statement:
 
```
for h with MarkRemove 
delete h
```
A query with an empty body has no effect and does not run.
