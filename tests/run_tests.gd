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


# ---------------------------------------------------------------- exhaustion, offline, route

func _ride(s, hours: float, dt := 2.0) -> void:
	for i in int(hours * 3600.0 / dt):
		s.step(dt)


func test_exhausted_rider_walks_steep_climb_in_big_gear() -> void:
	var s := _sim()
	s.glycogen_g = 0.0
	s.front = 1
	s.rear = s.cassette.size() - 1  # 50x11, far too big
	# Find a steep climb.
	var km := 0.0
	while s.terrain.grade_at(km) < 0.06 and km < 2000.0:
		km += 0.1
	s.distance_km = km
	s.step(2.0)
	check(s.walking, "bonked rider in 50x11 on %.1f %% should walk" % (s.grade * 100.0))
	check(s.speed_ms * 3.6 <= tuning.exhaustion.walk_speed_kmh + 0.01, "walking speed")


func test_unattended_rider_ends_up_sitting_and_stays_there() -> void:
	var s := _sim()
	_ride(s, 12.0, 4.0)
	check(s.sitting, "unattended rider should sit by the road within 12 h")
	var km := s.distance_km
	_ride(s, 4.0, 60.0)
	check(s.sitting, "rider never eats or drinks alone, so stays sitting")
	near(s.distance_km, km, 1e-6, "no distance while sitting")


func test_sitting_rider_gets_up_after_food_and_water() -> void:
	var s := _sim()
	s.sitting = true
	s.sit_reason = "dehydration"
	s.water_deficit_l = tuning.rider.mass_kg * 0.065
	s.glycogen_g = 0.0
	s.general_fatigue = 50.0
	check(s.roadside_help(), "help is available while sitting")
	while s.drink():
		pass
	s.eat_best()
	_ride(s, 0.5, 10.0)
	check(not s.sitting, "rider gets up once fed and watered")


func test_roadside_help_never_soft_locks() -> void:
	var s := _sim()
	s.sitting = true
	s.coins = 0.0
	s.water_deficit_l = 3.0
	check(s.roadside_help(), "broke rider still gets help")
	check(s.water_deficit_l < 3.0, "help gives water")
	check(s.gut_g > 0.0, "help gives food")


func test_catch_up_is_capped_and_reports() -> void:
	var s := _sim()
	var cap: float = tuning.offline.max_real_hours * 3600.0 * tuning.time_scale
	var r: Dictionary = s.catch_up(cap * 3.0)
	near(r.game_seconds, cap, 1.0, "offline time capped")
	check(r.km > 0.0, "some distance offline")
	check(r.sitting and r.sat_at_km > 0.0, "unfed rider sits by the road offline")


func test_offline_and_live_agree_roughly() -> void:
	var a := _sim()
	var b := _sim()
	_ride(a, 2.0, 2.0)
	b.catch_up(2.0 * 3600.0)
	check(absf(a.distance_km - b.distance_km) < 1.0, "live %.2f km vs offline %.2f km" % [a.distance_km, b.distance_km])


func test_route_finishes() -> void:
	var s := _sim()
	s.distance_km = tuning.route.length_km - 0.001
	s.glycogen_g = tuning.rider.glycogen_max_g
	for i in 10:
		s.step(2.0)
	check(s.finished, "route should finish")
	near(s.distance_km, tuning.route.length_km, 1e-6, "distance stops at the finish")
