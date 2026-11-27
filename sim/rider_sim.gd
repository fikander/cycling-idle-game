extends RefCounted
## The whole game simulation: rider, bike, body, road, money and training.
## It has no scene or rendering code, so it runs headless for balancing
## and the 3D game later just reads its state each frame.
##
## Time passed to step() is GAME seconds. The game loop multiplies real
## seconds by tuning.time_scale before calling it.

const Physics := preload("res://sim/bike_physics.gd")
const Terrain := preload("res://sim/terrain.gd")

signal shop_reached(km: float)
signal collapsed(reason: String)
signal level_up(stat: String, level: int)

var t: Dictionary  # tuning
var terrain: Terrain

# --- controls (what the player changes) ---
var cadence_target: float
var front: int
var rear: int
var stop_at_next_shop := false
var auto_drink := false
var auto_eat := false
var auto_shift := false

# --- bike and kit ---
var chainrings: Array
var cassette: Array
var bike_mass: float
var cda: float
var crr: float
var bottles: Array[float] = []
var bottle_capacity_l: float
var pocket_slots: int
var pockets: Array[String] = []

# --- body ---
var glycogen_g: float
var gut_g := 0.0
var water_deficit_l := 0.0
var general_fatigue := 0.0  # 0..100
var muscle_fatigue := 0.0  # 0..100

# --- world ---
var time_s := 0.0
var distance_km := 0.0
var coins := 0.0
var next_shop_km: float
var resting_s := 0.0
var rest_reason := ""

# --- training (xp per stat; level = floor(sqrt(xp / xp_per_level))) ---
var xp := {"endurance": 0.0, "stamina": 0.0, "strength": 0.0, "gut": 0.0, "cooling": 0.0}
var levels := {"endurance": 0, "stamina": 0, "strength": 0, "gut": 0, "cooling": 0}

# --- last step outputs, for the HUD and for stats ---
var speed_ms := 0.0
var power_w := 0.0
var cadence_rpm := 0.0
var grade := 0.0
var temperature_c := 0.0
var capacity := 1.0
var intensity := 0.0
var carb_burn_gph := 0.0
var sweat_lph := 0.0
var coasting := false
var grinding := false


func _init(tuning: Dictionary) -> void:
	t = tuning
	terrain = Terrain.new(t.terrain)
	var b: Dictionary = t.bike
	chainrings = b.chainrings.map(func(x): return int(x))
	cassette = b.cassette.map(func(x): return int(x))
	front = int(b.start_front)
	rear = int(b.start_rear)
	bike_mass = b.mass_kg
	cda = t.physics.cda
	crr = t.physics.crr
	bottle_capacity_l = b.bottle_capacity_l
	for i in int(b.bottle_count):
		bottles.append(bottle_capacity_l)
	pocket_slots = int(b.pocket_slots)
	for f in t.start_pockets:
		pockets.append(f)
	cadence_target = t.cadence.start_rpm
	glycogen_g = t.rider.glycogen_start_g
	next_shop_km = terrain.next_shop_after(0.0)


static func load_tuning(path := "res://config/tuning.json") -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "Could not parse %s" % path)
	return parsed


# ---------------------------------------------------------------- derived stats

func ftp() -> float:
	return t.rider.ftp_w * (1.0 + levels.endurance * t.training.endurance_ftp_per_level)


func total_mass() -> float:
	var water := 0.0
	for w in bottles:
		water += w
	return t.rider.mass_kg + bike_mass + water


func absorb_gph() -> float:
	return t.rider.gut_absorb_gph + levels.gut * t.training.gut_absorb_gph_per_level


func dehydration_pct() -> float:
	return water_deficit_l / t.rider.mass_kg * 100.0


func glycogen_ratio() -> float:
	return glycogen_g / t.rider.glycogen_max_g


func hour_of_day() -> float:
	return fmod(t.start_hour + time_s / 3600.0, 24.0)


func is_resting() -> bool:
	return resting_s > 0.0


func _phys() -> Dictionary:
	var p: Dictionary = t.physics.duplicate()
	p.cda = cda
	p.crr = crr
	return p


## Fraction of FTP the body can deliver right now (1.0 is fresh).
func current_capacity() -> float:
	var f: Dictionary = t.fatigue
	var e: Dictionary = t.energy_penalties
	var m := 1.0
	m *= 1.0 - f.general_penalty * pow(general_fatigue / 100.0, 2.0)
	m *= 1.0 - f.muscle_penalty * pow(muscle_fatigue / 100.0, 2.0)
	var r := glycogen_ratio()
	if r < e.bonk_threshold:
		m *= lerpf(e.bonk_floor, 1.0, r / e.bonk_threshold)
	var d: float = dehydration_pct()
	if d > e.dehydration_free_pct:
		m *= 1.0 - e.dehydration_penalty_per_pct * (d - e.dehydration_free_pct)
	if gut_g > t.rider.gut_capacity_g:
		m *= 1.0 - e.gut_overfill_penalty
	return clampf(m, 0.15, 1.0)


## Pedalling efficiency multiplier: best at the optimal cadence, worse either side.
func cadence_efficiency(rpm: float) -> float:
	var c: Dictionary = t.cadence
	var x: float = (rpm - c.optimal_rpm) / c.optimal_rpm
	return clampf(1.0 - c.efficiency_falloff * x * x, 0.6, 1.0)


# ---------------------------------------------------------------- player actions

func shift(delta_rear: int) -> void:
	rear = clampi(rear + delta_rear, 0, cassette.size() - 1)


func shift_front(index: int) -> void:
	front = clampi(index, 0, chainrings.size() - 1)


func set_cadence(rpm: float) -> void:
	cadence_target = clampf(rpm, t.cadence.min_rpm, t.cadence.max_rpm)


func eat(food_id: String) -> bool:
	var i := pockets.find(food_id)
	if i < 0:
		return false
	pockets.remove_at(i)
	var food: Dictionary = t.food[food_id]
	gut_g += food.carbs_g
	water_deficit_l = max(0.0, water_deficit_l - food.water_l)
	return true


## Eats the food with most carbs. Returns false when pockets are empty.
func eat_best() -> bool:
	if pockets.is_empty():
		return false
	var best := pockets[0]
	for f in pockets:
		if t.food[f].carbs_g > t.food[best].carbs_g:
			best = f
	return eat(best)


func drink() -> bool:
	for i in bottles.size():
		if bottles[i] > 0.0:
			var sip: float = min(bottles[i], t.hydration.sip_l)
			bottles[i] -= sip
			water_deficit_l = max(0.0, water_deficit_l - sip)
			return true
	return false


func water_left_l() -> float:
	var w := 0.0
	for b in bottles:
		w += b
	return w


## Gear that puts the rider closest to a target power at the target cadence.
func best_gear_for_power(target_w: float) -> Vector2i:
	var p := _phys()
	var best := Vector2i(front, rear)
	var best_err := INF
	for fi in chainrings.size():
		for ri in cassette.size():
			var v := Physics.gear_speed(cadence_target, chainrings[fi], cassette[ri], p.wheel_circumference_m)
			var err: float = abs(Physics.power_for_speed(v, grade, total_mass(), p) - target_w)
			if err < best_err:
				best_err = err
				best = Vector2i(fi, ri)
	return best


func apply_best_gear() -> void:
	var g := best_gear_for_power(ftp() * capacity * t.automation.target_intensity)
	front = g.x
	rear = g.y


## Buys food until pockets are full or money runs out. Cheapest carbs first.
func buy_food(food_id: String) -> bool:
	var price: float = t.food[food_id].price
	if coins < price or pockets.size() >= pocket_slots:
		return false
	coins -= price
	pockets.append(food_id)
	return true


func refill_bottles() -> void:
	for i in bottles.size():
		bottles[i] = bottle_capacity_l


# ---------------------------------------------------------------- simulation

func step(dt: float) -> void:
	time_s += dt
	grade = terrain.grade_at(distance_km)
	temperature_c = terrain.temperature_c(distance_km, hour_of_day())
	capacity = current_capacity()

	if resting_s > 0.0:
		_step_resting(dt)
		return

	_run_automations()

	var p := _phys()
	var mass := total_mass()
	var ring: int = chainrings[front]
	var cog: int = cassette[rear]
	var circ: float = p.wheel_circumference_m
	var v_gear := Physics.gear_speed(cadence_target, ring, cog, circ)
	var p_avail: float = ftp() * capacity * t.rider.effort_cap
	var p_req := Physics.power_for_speed(v_gear, grade, mass, p)
	var v_coast := Physics.coasting_speed(grade, mass, p)

	coasting = false
	grinding = false
	if v_coast >= v_gear:
		coasting = true
		speed_ms = v_coast
		power_w = 0.0
		cadence_rpm = 0.0
	elif p_req > p_avail:
		grinding = true
		power_w = p_avail
		speed_ms = Physics.speed_for_power(p_avail, grade, mass, p)
		cadence_rpm = Physics.cadence_for_speed(speed_ms, ring, cog, circ)
	else:
		power_w = p_req
		speed_ms = v_gear
		cadence_rpm = cadence_target

	intensity = power_w / ftp()
	_step_metabolism(dt, p_req)
	_step_hydration(dt)
	_step_fatigue(dt)
	_step_training(dt)

	var km := speed_ms * dt / 1000.0
	distance_km += km
	coins += km * t.economy.coins_per_km * terrain.biome_at(distance_km).coin_mult

	if distance_km >= next_shop_km:
		var at := next_shop_km
		next_shop_km = terrain.next_shop_after(at)
		shop_reached.emit(at)
		if stop_at_next_shop:
			stop_at_next_shop = false
			_start_rest(t.economy.shop_stop_minutes * 60.0, "shop")

	_check_collapse()


func _run_automations() -> void:
	var a: Dictionary = t.automation
	if auto_drink:
		while water_deficit_l > a.drink_deficit_l and drink():
			pass
	if auto_eat and glycogen_ratio() < a.eat_glycogen_ratio and gut_g < a.eat_gut_max_g:
		eat_best()
	if auto_shift:
		apply_best_gear()


func _step_metabolism(dt: float, _p_req: float) -> void:
	var eff: float = t.metabolism.gross_efficiency * cadence_efficiency(max(cadence_rpm, 1.0))
	var kcal_h: float = power_w * 3600.0 / (eff * 4184.0)
	var frac := Physics.curve(t.metabolism.carb_fraction_curve, intensity)
	carb_burn_gph = kcal_h * frac / 4.0
	glycogen_g -= carb_burn_gph * dt / 3600.0
	_absorb(dt)


func _absorb(dt: float) -> void:
	var absorbed: float = min(gut_g, absorb_gph() * dt / 3600.0)
	gut_g -= absorbed
	glycogen_g = clampf(glycogen_g + absorbed, 0.0, t.rider.glycogen_max_g)
	xp.gut += absorbed / 100.0 * t.training.gut_xp_per_100g


func _step_hydration(dt: float) -> void:
	var h: Dictionary = t.hydration
	var heat: float = 1.0 + h.heat_factor_per_c * max(0.0, temperature_c - h.heat_threshold_c)
	var cooling: float = 1.0 - levels.cooling * t.training.cooling_sweat_per_level
	sweat_lph = t.rider.base_sweat_lph * (0.4 + 0.6 * power_w / h.reference_power_w) * heat * cooling
	var sweat: float = sweat_lph * dt / 3600.0
	water_deficit_l += sweat
	if temperature_c > h.heat_threshold_c:
		xp.cooling += sweat * t.training.cooling_xp_per_hot_l


func _step_fatigue(dt: float) -> void:
	var f: Dictionary = t.fatigue
	var hours := dt / 3600.0
	var stamina: float = 1.0 - levels.stamina * t.training.stamina_fatigue_per_level
	var strength: float = 1.0 - levels.strength * t.training.strength_muscle_per_level

	if intensity < f.recovery_intensity:
		general_fatigue -= f.general_recovery_per_h * (f.recovery_intensity - intensity) / f.recovery_intensity * hours
	general_fatigue += f.general_rate_per_h * pow(intensity, f.general_exponent) * stamina * hours

	# Torque relative to riding at FTP at the optimal cadence.
	var torque_rel := 0.0
	if cadence_rpm > 1.0:
		torque_rel = (power_w / cadence_rpm) / (ftp() / t.cadence.optimal_rpm)
	var over: float = max(0.0, torque_rel - f.muscle_torque_threshold)
	muscle_fatigue += f.muscle_rate_per_h * over * over * strength * hours
	if over <= 0.0:
		muscle_fatigue -= f.muscle_recovery_per_h * hours
	xp.strength += over * hours * t.training.strength_xp_per_torque_h

	general_fatigue = clampf(general_fatigue, 0.0, 100.0)
	muscle_fatigue = clampf(muscle_fatigue, 0.0, 100.0)


func _step_training(dt: float) -> void:
	var hours := dt / 3600.0
	var tr: Dictionary = t.training
	if intensity > 0.5:
		xp.endurance += hours * tr.endurance_xp_per_h * min(intensity, 1.0)
	xp.stamina += hours * tr.endurance_xp_per_h * 0.5
	for stat in xp:
		var lvl := mini(int(floor(sqrt(xp[stat] / tr.xp_per_level))), int(tr.max_level))
		if lvl > levels[stat]:
			levels[stat] = lvl
			level_up.emit(stat, lvl)


func _step_resting(dt: float) -> void:
	resting_s -= dt
	speed_ms = 0.0
	power_w = 0.0
	cadence_rpm = 0.0
	intensity = 0.0
	var hours := dt / 3600.0
	general_fatigue = max(0.0, general_fatigue - t.fatigue.rest_recovery_per_h * hours)
	muscle_fatigue = max(0.0, muscle_fatigue - t.fatigue.rest_recovery_per_h * hours)
	carb_burn_gph = t.rider.resting_kcal_h * 0.5 / 4.0
	glycogen_g = max(0.0, glycogen_g - carb_burn_gph * hours)
	_absorb(dt)
	if rest_reason == "shop":
		refill_bottles()
		# At a shop the rider can drink as much as needed for free.
		water_deficit_l = max(0.0, water_deficit_l - 1.0 * hours * 6.0)
	if resting_s <= 0.0:
		resting_s = 0.0
		rest_reason = ""


func _start_rest(seconds: float, reason: String) -> void:
	resting_s = seconds
	rest_reason = reason


func _check_collapse() -> void:
	var e: Dictionary = t.energy_penalties
	var reason := ""
	if dehydration_pct() >= e.dehydration_collapse_pct:
		reason = "dehydration"
	elif general_fatigue >= 100.0:
		reason = "exhaustion"
	if reason != "":
		# A passer-by helps out: some water, a long rest.
		water_deficit_l = min(water_deficit_l, t.rider.mass_kg * 0.02)
		general_fatigue = min(general_fatigue, 85.0)
		_start_rest(e.collapse_rest_h * 3600.0, reason)
		collapsed.emit(reason)


# ---------------------------------------------------------------- save / load

func to_save() -> Dictionary:
	return {
		"version": 1,
		"time_s": time_s, "distance_km": distance_km, "coins": coins,
		"front": front, "rear": rear, "cadence_target": cadence_target,
		"bottles": bottles, "pockets": pockets,
		"glycogen_g": glycogen_g, "gut_g": gut_g, "water_deficit_l": water_deficit_l,
		"general_fatigue": general_fatigue, "muscle_fatigue": muscle_fatigue,
		"xp": xp, "levels": levels, "next_shop_km": next_shop_km,
		"resting_s": resting_s, "rest_reason": rest_reason,
		"auto": [auto_drink, auto_eat, auto_shift],
	}


func load_save(d: Dictionary) -> void:
	time_s = d.time_s
	distance_km = d.distance_km
	coins = d.coins
	front = int(d.front)
	rear = int(d.rear)
	cadence_target = d.cadence_target
	bottles.assign(d.bottles)
	pockets.assign(d.pockets)
	glycogen_g = d.glycogen_g
	gut_g = d.gut_g
	water_deficit_l = d.water_deficit_l
	general_fatigue = d.general_fatigue
	muscle_fatigue = d.muscle_fatigue
	xp = d.xp
	for k in d.levels:
		levels[k] = int(d.levels[k])
	next_shop_km = d.next_shop_km
	resting_s = d.resting_s
	rest_reason = d.rest_reason
	auto_drink = d.auto[0]
	auto_eat = d.auto[1]
	auto_shift = d.auto[2]
