## Hello World

```
module test

on load do
	print "Hello World"
end
```

## Simple Movement

```
module movement

define Position component (
	value Vector3
)

define Velocity component ( 
	value Vector3
)

const speed = 10

on load do
	create Entity with
		Position,
		Velocity(Vector3.left * speed)
end

on tick
for entity with Position, Velocity do
	entity.Position.value += entity.Velocity.value
end

```

## 