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

define component Position (
	Vector3 value
)

define component Velocity ( 
	Vector3 value
)

const speed = 10

on load do
	create entity with
		Position,
		Velocity(Vector3.left * speed)
end

on tick
for entity with Position, Velocity do
	entity.Position.value += entity.Velocity.value
end

```

## 