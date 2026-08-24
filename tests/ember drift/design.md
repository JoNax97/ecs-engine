# Ember Drift — Vertical Slice Design Brief

## Premise

A single dry hillside burns in real time. Fire, air and animals all run continuously against each other, and nothing waits for the player. The slice is self-contained: it hooks into no other mechanic.

## What exists

**Brush** covers the hillside in patches. Each patch accumulates heat, which rises when something nearby burns and bleeds off at 6 per second otherwise, and char, which only ever goes up. A patch ignites when heat crosses 100, burns 12 seconds, then collapses to ash: permanently unburnable, though still hot for a while.

**Embers** are airborne sparks thrown off by burning brush, about two per second per patch. An ember lives 4 seconds, drifts with the wind, and dumps 60 heat where it lands — enough to prime a cold patch, never enough to ignite one alone.

**Smoke** pools above burning and freshly-charred ground, gaining 1 density per second per burning patch and draining at 0.4 per second while it drifts downwind. At density 3 or higher the air is oxygen-poor and an ember landing under it delivers only half its heat.

**Cinder Moths** roost on unburnt brush in clusters of 5 to 20. They are calm, they nibble, and they dry the patch beneath them at 2 heat per second per moth. They are the reason a hillside starts burning at all.

## How it behaves

Wind is one hillside-wide direction and speed that re-rolls its heading every 20 to 40 seconds. It carries embers and smoke together, and that shared carrier is the coupling: a strong steady wind drives the fire fast but also lays a smoke blanket ahead of the front that suppresses the very embers doing the driving. Fire advances in surges rather than a smooth line.

Moths react to discrete events, not to gradual warming. When a patch ignites, every moth within 8 metres startles instantly; an ember landing within 3 metres does the same. A startled moth reroosts on the coolest unburnt patch within 25 metres, which concentrates moths just ahead of the fire and pre-heats the ground it is about to reach. Long-roosted patches carry real accumulated heat, so the front accelerates into moth-dense ground and stalls where the moths have already fled.

Char persists after the flame. Ash blocks spread entirely, so burnt-out ground becomes a firebreak the player can steer the front around, and smoke lingering over that ash keeps suppressing embers for several seconds after the flame dies.

## Edge cases

A cluster that startles into a pocket fully surrounded by ash has nowhere cooler to go. It roosts in place and heats ground that can never ignite. Intended: a legible dead end, not a bug.

Two fronts converging on one narrow strip stack smoke past density 3 fast enough to smother it, and the gap survives between two burnt regions.

Wind dropping to near zero over a large fire lets smoke sit on its own source. The fire chokes itself, embers land at half strength, and spread nearly halts until the wind re-rolls.
