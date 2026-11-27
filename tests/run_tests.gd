extends SceneTree
## Minimal test runner, no plugins needed.
## Run:  godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any test fails.

const Physics := preload("res://sim/bike_physics.gd")
const Terrain := preload("res://sim/terrain.gd")
const RiderSim := preload("res://sim/rider_sim.gd")

var tuning: Dictionary
var failures := 0
var passed := 0


func _init() -> void:
	tuning = RiderSim.load_tuning()
	for m in get_method_list():
		var n: String = m.name
		if n.begins_with("test_"):
			var before := failures
			call(n)
			if failures == before:
				passed += 1
				print("  ok    %s" % n)
			else:
				print("  FAIL  %s" % n)
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("    %s" % msg)


func near(a: float, b: float, tol: float, msg: String) -> void:
	check(absf(a - b) <= tol, "%s: expected %.3f, got %.3f" % [msg, b, a])


func _sim() -> RiderSim:
	return RiderSim.new(tuning)


# ---------------------------------------------------------------- physics

func test_flat_power_is_realistic() -> void:
	var p: Dictionary = tuning.physics
	var w := Physics.power_for_speed(30.0 / 3.6, 0.0, 82.5, p)
	check(w > 130.0 and w < 260.0, "30 km/h on the flat should need 130-260 W, got %.0f" % w)


func test_speed_for_power_inverts_power_for_speed() -> void:
	var p: Dictionary = tuning.physics
	for g in [-0.02, 0.0, 0.04, 0.08]:
		var v := Physics.speed_for_power(200.0, g, 82.5, p)
		near(Physics.power_for_speed(v, g, 82.5, p), 200.0, 1.0, "inverse at grade %s" % g)


func test_coasting_only_downhill() -> void:
	var p: Dictionary = tuning.physics
	check(Physics.coasting_speed(0.0, 82.5, p) == 0.0, "no coasting on the flat")
	check(Physics.coasting_speed(0.03, 82.5, p) == 0.0, "no coasting uphill")
	check(Physics.coasting_speed(-0.05, 82.5, p) > 8.0, "should roll fast down 5 %")
	check(Physics.coasting_speed(-0.10, 82.5, p) <= p.max_descent_speed_ms, "descent speed capped")


func test_gear_and_cadence_roundtrip() -> void:
	var v := Physics.gear_speed(90.0, 50, 17, 2.1)
	near(Physics.cadence_for_speed(v, 50, 17, 2.1), 90.0, 0.001, "cadence roundtrip")


func test_curve_lookup() -> void:
	var c := [[0.0, 0.0], [1.0, 10.0], [2.0, 30.0]]
	near(Physics.curve(c, -1.0), 0.0, 1e-6, "clamp low")
	near(Physics.curve(c, 0.5), 5.0, 1e-6, "interpolate")
	near(Physics.curve(c, 1.5), 20.0, 1e-6, "interpolate second span")
	near(Physics.curve(c, 9.0), 30.0, 1e-6, "clamp high")


# ---------------------------------------------------------------- terrain

func test_terrain_is_deterministic() -> void:
	var a := Terrain.new(tuning.terrain)
	var b := Terrain.new(tuning.terrain)
	for km in [0.0, 12.3, 150.0, 999.9]:
		near(a.elevation_m(km), b.elevation_m(km), 1e-6, "same seed same road at %s" % km)


func test_terrain_starts_in_fields_and_grades_are_capped() -> void:
	var tr := Terrain.new(tuning.terrain)
	check(tr.biome_at(1.0).id == "fields", "first segment should be fields")
	var cap: float = tuning.terrain.max_grade
	for i in 2000:
		var g := tr.grade_at(i * 0.25)
		check(absf(g) <= cap + 1e-6, "grade %.3f beyond cap at %.2f km" % [g, i * 0.25])
		if absf(g) > cap + 1e-6:
			return


func test_shops_are_ahead_and_spaced() -> void:
	var tr := Terrain.new(tuning.terrain)
	var km := 0.0
	for i in 20:
		var nxt := tr.next_shop_after(km)
		check(nxt > km, "next shop must be ahead")
		check(nxt - km < tuning.terrain.shop_every_km * 2.0, "shops too far apart: %.1f km" % (nxt - km))
		km = nxt


# ---------------------------------------------------------------- rider

func test_eating_fills_gut_and_absorbs_into_glycogen() -> void:
	var s := _sim()
	s.glycogen_g = 200.0
	check(s.eat("bar"), "should eat a bar from starting pockets")
	near(s.gut_g, tuning.food.bar.carbs_g, 1e-6, "bar goes to gut")
	s.set_cadence(0.0)
	s.resting_s = 3600.0
	s.step(600.0)
	check(s.glycogen_g > 200.0, "absorbed carbs refill glycogen")
	check(s.gut_g < tuning.food.bar.carbs_g, "gut empties over time")


func test_cannot_eat_what_you_do_not_have() -> void:
	var s := _sim()
	s.pockets.clear()
	check(not s.eat("gel"), "eating from empty pockets fails")
	check(not s.eat_best(), "eat_best with empty pockets fails")


func test_drinking_reduces_deficit_and_empties_bottles() -> void:
	var s := _sim()
	s.water_deficit_l = 1.0
	var before := s.water_left_l()
	check(s.drink(), "should drink")
	near(s.water_deficit_l, 1.0 - tuning.hydration.sip_l, 1e-6, "deficit down by one sip")
	near(s.water_left_l(), before - tuning.hydration.sip_l, 1e-6, "bottle down by one sip")


func test_bonk_and_dehydration_reduce_capacity() -> void:
	var s := _sim()
	near(s.current_capacity(), 1.0, 1e-6, "fresh rider at full capacity")
	s.glycogen_g = 0.0
	check(s.current_capacity() <= tuning.energy_penalties.bonk_floor + 1e-6, "empty glycogen means bonk")
	s.glycogen_g = tuning.rider.glycogen_max_g
	s.water_deficit_l = tuning.rider.mass_kg * 0.04
	check(s.current_capacity() < 0.9, "4 % dehydration hurts")


func test_overeating_hurts() -> void:
	var s := _sim()
	s.gut_g = tuning.rider.gut_capacity_g + 10.0
	check(s.current_capacity() < 1.0, "overfull gut reduces capacity")


func test_cadence_efficiency_peaks_at_optimum() -> void:
	var s := _sim()
	var opt: float = tuning.cadence.optimal_rpm
	check(s.cadence_efficiency(opt) > s.cadence_efficiency(opt - 30.0), "low cadence less efficient")
	check(s.cadence_efficiency(opt) > s.cadence_efficiency(opt + 30.0), "high cadence less efficient")


func test_best_gear_is_easier_on_climbs() -> void:
	var s := _sim()
	s.grade = 0.0
	var flat := s.best_gear_for_power(140.0)
	s.grade = 0.07
	var climb := s.best_gear_for_power(140.0)
	var ratio_flat: float = float(s.chainrings[flat.x]) / s.cassette[flat.y]
	var ratio_climb: float = float(s.chainrings[climb.x]) / s.cassette[climb.y]
	check(ratio_climb < ratio_flat, "climbing gear should be lower than flat gear")


func test_unattended_rider_eventually_bonks() -> void:
	var s := _sim()
	var dt: float = tuning.sim_step_s
	for i in int(8 * 3600 / dt):
		s.step(dt)
	check(s.glycogen_ratio() < tuning.energy_penalties.bonk_threshold, "no food for 8 h must bonk")
	check(s.distance_km > 100.0, "should still cover ground, got %.1f km" % s.distance_km)


func test_riding_earns_coins_and_xp() -> void:
	var s := _sim()
	for i in 1800:
		s.step(2.0)
	check(s.coins > 0.0, "coins from distance")
	check(s.xp.endurance > 0.0, "endurance xp from riding")


func test_shop_stop_refills_bottles() -> void:
	var s := _sim()
	for i in s.bottles.size():
		s.bottles[i] = 0.0
	s.stop_at_next_shop = true
	s.distance_km = s.next_shop_km - 0.001
	for i in 30:
		s.step(2.0)
	check(s.is_resting() and s.rest_reason == "shop", "rider should stop at shop")
	check(s.water_left_l() > 1.0, "bottles refilled at shop")


func test_save_load_roundtrip() -> void:
	var a := _sim()
	for i in 500:
		a.step(2.0)
	a.eat_best()
	var data: Dictionary = JSON.parse_string(JSON.stringify(a.to_save()))
	var b := _sim()
	b.load_save(data)
	near(b.distance_km, a.distance_km, 1e-6, "distance")
	near(b.glycogen_g, a.glycogen_g, 1e-6, "glycogen")
	check(b.pockets == a.pockets, "pockets")
	check(b.rear == a.rear and b.front == a.front, "gears")
	a.step(2.0)
	b.step(2.0)
	near(b.distance_km, a.distance_km, 1e-6, "same state continues identically")
