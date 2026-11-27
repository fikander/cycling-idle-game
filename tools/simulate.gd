extends SceneTree
## Headless pacing simulation. Plays the game with different "player habits"
## and prints how far the rider gets and what goes wrong.
##
## Run:  godot --headless --path . --script res://tools/simulate.gd
## Optional args after "--":  minutes=120  scenario=checkin_5
##
## Times below are REAL minutes (what the player feels); the sim converts
## them with tuning.time_scale.

const RiderSim := preload("res://sim/rider_sim.gd")

const CHECKPOINTS_MIN := [15, 30, 60, 120]

## Each scenario: how often the player checks in (real minutes, 0 = never),
## and whether automation upgrades are owned.
const SCENARIOS := {
	"unattended": {"checkin_min": 0.0, "auto": false},
	"checkin_2": {"checkin_min": 2.0, "auto": false},
	"checkin_5": {"checkin_min": 5.0, "auto": false},
	"checkin_10": {"checkin_min": 10.0, "auto": false},
	"checkin_20": {"checkin_min": 20.0, "auto": false},
	"automated_checkin_20": {"checkin_min": 20.0, "auto": true},
}


func _init() -> void:
	var args := _parse_args()
	var tuning := RiderSim.load_tuning()
	var minutes: float = float(args.get("minutes", "120"))
	var only: String = args.get("scenario", "")

	print("Ultra Idle Cycling: pacing simulation")
	print("time_scale=%.0fx  (1 real minute = %.0f game minutes)\n" % [tuning.time_scale, tuning.time_scale])
	_print_terrain(tuning)
	for name in SCENARIOS:
		if only != "" and name != only:
			continue
		run_scenario(name, SCENARIOS[name], tuning, minutes)
	if only == "" or only == "offline":
		print("== offline: 15 min of play with check-ins every 5 min, then the game is closed ==")
		for h in [0.5, 2.0, 8.0]:
			run_offline(tuning, h)
	quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out


func _print_terrain(tuning: Dictionary) -> void:
	var sim := RiderSim.new(tuning)
	var line := "Route (first 400 km): "
	for seg in 5:
		var km := seg * float(tuning.terrain.segment_km)
		line += "%d km %s | " % [km, sim.terrain.biome_at(km + 1.0).id]
	print(line)
	var shops := []
	var k := 0.0
	for i in 6:
		k = sim.terrain.next_shop_after(k)
		shops.append("%.0f" % k)
	print("Shops at km: %s ..." % ", ".join(shops))
	var steepest := 0.0
	for i in 4000:
		steepest = max(steepest, abs(sim.terrain.grade_at(i * 0.1)))
	print("Steepest grade in first 400 km: %.1f %%\n" % (steepest * 100.0))


## A player's check-in: fix the gear, eat, drink, plan a shop stop.
func check_in(sim) -> void:
	if sim.sitting and sim.pockets.is_empty() and sim.water_left_l() <= 0.0:
		sim.roadside_help()
	sim.apply_best_gear()
	# Eat up to what the gut can hold, unless the tank is nearly full.
	while sim.glycogen_ratio() < 0.9 and sim.gut_g < 60.0 and sim.eat_best():
		pass
	while sim.water_deficit_l > 0.1 and sim.drink():
		pass
	if sim.water_left_l() < 1.0 or sim.pockets.size() < sim.pocket_slots - 1:
		sim.stop_at_next_shop = true


func _on_shop(_km: float, sim) -> void:
	if not sim.stop_at_next_shop:
		return
	while sim.buy_food("rice_cake"):
		pass


func run_scenario(name: String, sc: Dictionary, tuning: Dictionary, minutes: float) -> Dictionary:
	var sim := RiderSim.new(tuning)
	var sit_downs := []
	sim.sat_down.connect(func(reason): sit_downs.append([sim.distance_km, reason]))
	sim.shop_reached.connect(_on_shop.bind(sim))
	if sc.auto:
		sim.auto_drink = true
		sim.auto_eat = true
		sim.auto_shift = true

	var dt: float = tuning.sim_step_s
	var scale: float = tuning.time_scale
	var total_game_s := minutes * 60.0 * scale
	var checkin_game_s: float = sc.checkin_min * 60.0 * scale
	var next_checkin := checkin_game_s
	var low_capacity_s := 0.0
	var bonk_s := 0.0
	var grind_s := 0.0
	var walk_s := 0.0
	var sit_s := 0.0
	var first_bonk_min := -1.0
	var cp_index := 0

	print("== %s (check-ins: %s, automation %s) ==" % [
		name, "never" if sc.checkin_min <= 0.0 else "%.0f real min" % sc.checkin_min, "on" if sc.auto else "off"])
	print("  real min |    km | km/h | coins | glyc % | dehyd % | fatigue gen/mus | levels E/S/St/G/C | food water")

	while sim.time_s < total_game_s:
		if checkin_game_s > 0.0 and sim.time_s >= next_checkin:
			check_in(sim)
			next_checkin += checkin_game_s
		sim.step(dt)
		if sim.sitting:
			sit_s += dt
		elif sim.walking:
			walk_s += dt
		if not sim.is_resting() and not sim.sitting:
			if sim.capacity < 0.8:
				low_capacity_s += dt
			if sim.glycogen_ratio() < tuning.energy_penalties.bonk_threshold:
				bonk_s += dt
				if first_bonk_min < 0.0:
					first_bonk_min = sim.time_s / scale / 60.0
			if sim.grinding:
				grind_s += dt
		var real_min := sim.time_s / scale / 60.0
		if cp_index < CHECKPOINTS_MIN.size() and real_min >= CHECKPOINTS_MIN[cp_index]:
			if CHECKPOINTS_MIN[cp_index] <= minutes:
				_print_row(sim, real_min)
			cp_index += 1

	var ride_h := sim.time_s / 3600.0
	print("  first bonk: %s | time bonked %.0f%% | weak (<80%% capacity) %.0f%% | grinding %.0f%% | walking %.0f%% | sitting %.0f%%" % [
		"none" if first_bonk_min < 0.0 else "%.1f real min" % first_bonk_min,
		bonk_s / sim.time_s * 100.0, low_capacity_s / sim.time_s * 100.0,
		grind_s / sim.time_s * 100.0, walk_s / sim.time_s * 100.0, sit_s / sim.time_s * 100.0])
	print("  sat down: %s\n" % ("never" if sit_downs.is_empty() else
		", ".join(sit_downs.map(func(c): return "%s at %.0f km" % [c[1], c[0]]))))
	return {"km": sim.distance_km, "avg_kmh": sim.distance_km / ride_h, "sit_downs": sit_downs.size(),
		"bonk_frac": bonk_s / sim.time_s}


## Plays 15 attentive minutes, then closes the game for a while.
func run_offline(tuning: Dictionary, hours_away: float) -> void:
	var sim := RiderSim.new(tuning)
	var dt: float = tuning.sim_step_s
	var scale: float = tuning.time_scale
	var next_checkin := 5.0 * 60.0 * scale
	while sim.time_s < 15.0 * 60.0 * scale:
		if sim.time_s >= next_checkin:
			check_in(sim)
			next_checkin += 5.0 * 60.0 * scale
		sim.step(dt)
	check_in(sim)
	var km_before: float = sim.distance_km
	var r: Dictionary = sim.catch_up(hours_away * 3600.0 * scale)
	var sat := "kept riding"
	if r.sat_at_km >= 0.0:
		sat = "sat down (%s) at %.0f km, %.0f real min after closing" % [
			r.sit_reason, r.sat_at_km, r.sat_after_game_s / scale / 60.0]
	print("  away %4.1f h: %.0f km -> +%.0f km, +%.0f coins, %s" % [
		hours_away, km_before, r.km, r.coins, sat])


func _print_row(sim, real_min: float) -> void:
	var lv: Dictionary = sim.levels
	print("  %8.0f | %5.1f | %4.1f | %5.0f | %6.0f | %7.1f | %7.0f / %-5.0f | %2d/%2d/%2d/%2d/%2d    | %4d %5.2f" % [
		real_min, sim.distance_km, sim.distance_km / (sim.time_s / 3600.0), sim.coins,
		sim.glycogen_ratio() * 100.0, sim.dehydration_pct(),
		sim.general_fatigue, sim.muscle_fatigue,
		lv.endurance, lv.stamina, lv.strength, lv.gut, lv.cooling,
		sim.pockets.size(), sim.water_left_l()])
