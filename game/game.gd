extends Node
## Main game: runs the simulation in real time, drives the 3D view and the
## HUD, and handles saving, offline catch-up and the small window mode.

const RiderSim := preload("res://sim/rider_sim.gd")
const World := preload("res://game/world.gd")
const Rider := preload("res://game/rider.gd")
const Hud := preload("res://game/hud.gd")

const SAVE_PATH := "user://save.json"
const AUTOSAVE_S := 15.0
const MINI_SIZE := Vector2i(480, 300)
const FULL_BASE := Vector2i(960, 540)
## Debug-only time warp on top of the normal time scale (keys 1-4).
const WARPS := [1.0, 5.0, 20.0, 60.0]

var tuning: Dictionary
var sim: RiderSim
var world: World
var rider: Rider
var camera: Camera3D
var hud: Hud

var time_scale := 10.0
var warp := 1.0
var sim_running := true
var saving_enabled := true
var mini := false
var _full_window_size := Vector2i(1280, 720)
var _autosave := AUTOSAVE_S
var _cam_offset := Vector3(-7.5, 2.8, -4.0)
var _shop_warned := false
var _last_state := ""
var _lane := 1.6


func _ready() -> void:
	saving_enabled = not get_tree().has_meta("no_save")
	tuning = RiderSim.load_tuning()
	time_scale = tuning.time_scale
	_start_sim(RiderSim.new(tuning))
	if saving_enabled:
		load_game()
	get_tree().set_auto_accept_quit(false)


func _start_sim(new_sim: RiderSim) -> void:
	sim = new_sim
	sim.level_up.connect(func(stat, lvl): hud.toast("%s level %d!" % [stat.capitalize(), lvl]))
	sim.sat_down.connect(func(reason): hud.toast("Your rider sat down by the road (%s)" % reason))
	sim.got_up.connect(func(): hud.toast("Back on the bike!"))
	sim.route_finished.connect(func(): hud.toast("Finish line!"))
	sim.shop_reached.connect(_on_shop_reached)
	for n in [world, rider, camera, hud]:
		if n:
			n.queue_free()
	world = World.new()
	add_child(world)
	world.setup(sim)
	rider = Rider.new()
	world.add_child(rider)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 2500.0
	camera.near = 0.1
	world.add_child(camera)
	camera.make_current()
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	_update_view(0.0)


func _process(delta: float) -> void:
	if sim_running:
		var game_dt := minf(delta, 0.25) * time_scale * warp
		var max_step: float = tuning.sim_step_s
		while game_dt > 0.0:
			var dt := minf(game_dt, max_step)
			sim.step(dt)
			game_dt -= dt
	_watch_state()
	_update_view(delta)
	if saving_enabled:
		_autosave -= delta
		if _autosave <= 0.0:
			_autosave = AUTOSAVE_S
			save_game()


func _update_view(delta: float) -> void:
	var m: float = sim.distance_km * 1000.0
	world.update_view(m)
	world.set_time_of_day(sim.hour_of_day())
	# At a shop the rider sits by the door; stranded riders pull over.
	var lane := 1.6
	if sim.is_at_shop():
		lane = 8.0
	elif sim.sitting:
		lane = 5.6
	_lane = lerpf(_lane, lane, 1.0 - exp(-3.0 * delta)) if delta > 0.0 else lane
	var pos := world.road_point(m, _lane)
	var fwd := world.road_forward(m)
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	rider.global_transform = Transform3D(Basis(fwd, up, right), pos)
	var pose := Rider.Pose.RIDE
	if sim.sitting or sim.is_at_shop():
		pose = Rider.Pose.SIT
	elif sim.walking:
		pose = Rider.Pose.WALK
	rider.animate(delta, sim.cadence_rpm, sim.speed_ms * time_scale * warp, pose)

	# Camera: behind and to the left, looking past the rider at the road ahead.
	var want := Vector3(-7.5, 2.8, -4.2) if not mini else Vector3(-6.0, 2.2, -3.4)
	if pose == Rider.Pose.SIT:
		want = Vector3(-4.5, 2.2, -6.0)
	_cam_offset = _cam_offset.lerp(want, 1.0 - exp(-2.0 * delta)) if delta > 0.0 else want
	var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
	var flat_right := flat_fwd.cross(Vector3.UP)
	var cam_pos := pos + flat_fwd * _cam_offset.x + Vector3.UP * _cam_offset.y + flat_right * _cam_offset.z
	var ground := world.ground_height(m + _cam_offset.x, _cam_offset.z, world.biome_mix(m)) + 1.0
	cam_pos.y = maxf(cam_pos.y, ground)
	camera.global_position = cam_pos
	camera.look_at(pos + flat_fwd * 4.0 + Vector3.UP * 0.9, Vector3.UP)


## Messages for things that change while the player isn't looking.
func _watch_state() -> void:
	var state := "ride"
	if sim.walking:
		state = "walk"
	elif sim.glycogen_ratio() < sim.t.energy_penalties.bonk_threshold:
		state = "bonk"
	if state != _last_state:
		if state == "walk":
			hud.toast("Too hard to pedal – walking. Shift to an easier gear!")
		elif state == "bonk":
			hud.toast("Bonk! Energy is almost empty – eat something")
		_last_state = state
	var to_shop: float = sim.next_shop_km - sim.distance_km
	if to_shop < 3.0 and not _shop_warned:
		_shop_warned = true
		if not sim.stop_at_next_shop:
			hud.toast("Shop in %.0f km – tap \"Stop at shop\" to stop" % ceil(to_shop))
	elif to_shop >= 3.0:
		_shop_warned = false


func _on_shop_reached(_km: float) -> void:
	if sim.is_at_shop():
		hud.toast("At the shop: bottles refilled" + (" (switch to full view to buy things)" if mini else ""))


# ---------------------------------------------------------------- actions

func do_drink() -> void:
	if not sim.drink():
		hud.toast("Bottles are empty")


func do_eat(id: String) -> void:
	if sim.gut_g > sim.t.rider.gut_capacity_g:
		hud.toast("Stomach is full – eating more will hurt")
	sim.eat(id)


func do_eat_best() -> void:
	if not sim.eat_best():
		hud.toast("No food left")


func do_roadside_help() -> void:
	if sim.roadside_help():
		hud.toast("A kind driver stops with water and a sandwich")


func new_ride() -> void:
	_start_sim(RiderSim.new(tuning))
	save_game()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_Q: sim.shift(-1)
		KEY_E: sim.shift(1)
		KEY_F: sim.shift_front(1 - sim.front)
		KEY_A: sim.set_cadence(sim.cadence_target - 5.0)
		KEY_D: sim.set_cadence(sim.cadence_target + 5.0)
		KEY_W: do_drink()
		KEY_S: do_eat_best()
		KEY_M: toggle_mini()
		KEY_1, KEY_2, KEY_3, KEY_4:
			if OS.is_debug_build():
				warp = WARPS[event.keycode - KEY_1]
		KEY_F9:
			if OS.is_debug_build():
				new_ride()


func warp_label() -> String:
	return "" if warp == 1.0 else "⏩ ×%d (debug)" % int(warp)


# ---------------------------------------------------------------- small window

func can_mini() -> bool:
	return OS.has_feature("pc") and DisplayServer.get_name() != "headless"


func toggle_mini() -> void:
	if not can_mini():
		return
	set_mini(not mini)


func set_mini(on: bool) -> void:
	mini = on
	var win := get_window()
	if on:
		_full_window_size = win.size
		win.borderless = false
		win.always_on_top = true
		win.size = MINI_SIZE
		win.content_scale_size = MINI_SIZE
		var screen := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(screen)
		win.position = area.position + area.size - MINI_SIZE - Vector2i(16, 16)
	else:
		win.always_on_top = false
		win.size = _full_window_size
		win.content_scale_size = FULL_BASE
		var area2 := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		win.position = area2.position + (area2.size - _full_window_size) / 2
	hud.set_mini(on)


# ---------------------------------------------------------------- save / load

func save_game() -> void:
	if not saving_enabled:
		return
	var data := {"sim": sim.to_save(), "saved_at": Time.get_unix_time_from_system()}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary) or not parsed.has("sim"):
		return
	sim.load_save(parsed.sim)
	var away: float = Time.get_unix_time_from_system() - float(parsed.get("saved_at", 0.0))
	if away > 30.0:
		var r: Dictionary = sim.catch_up(away * time_scale)
		hud.show_away(away, r)
	_update_view(0.0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_game()
		NOTIFICATION_APPLICATION_RESUMED:
			# Phones freeze the app in the background: catch up on return.
			if saving_enabled and FileAccess.file_exists(SAVE_PATH):
				var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
				if parsed is Dictionary:
					var away: float = Time.get_unix_time_from_system() - float(parsed.get("saved_at", 0.0))
					if away > 30.0:
						hud.show_away(away, sim.catch_up(away * time_scale))
