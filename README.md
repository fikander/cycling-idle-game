# Ultra Idle Cycling

An idle game about an ultra-distance cyclist. Keep it open in the corner of your screen and manage cadence, gears, carbs and water as the road rolls through cel-shaded landscapes.

Built with [Godot 4.7](https://godotengine.org/). See [docs/DESIGN.md](docs/DESIGN.md) for the design.

## Status

Step 1 of the prototype: the simulation core. There's no 3D scene yet.

## Running

Requires Godot 4.7 on your PATH as `godot`.

```sh
# Unit tests
godot --headless --path . --script res://tests/run_tests.gd

# Pacing simulation (2 real hours, all player types)
godot --headless --path . --script res://tools/simulate.gd

# One scenario, custom length
godot --headless --path . --script res://tools/simulate.gd -- minutes=30 scenario=checkin_5
```

All balance numbers are in `config/tuning.json`. Change them and rerun the simulation to see the effect.
