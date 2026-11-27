extends SceneTree
## Renders screenshots of the game at chosen places and times. Needs a
## display (on a headless server use xvfb-run).
## Run:  godot --path . --rendering-driver opengl3 --script res://tools/screenshot.gd -- out=shots
##
## Each shot: [file name, km, hour, pose, mini]

const SHOTS := [
	["fields_morning", 8.0, 9.0, "ride", false],
	["coast_afternoon", 110.0, 15.5, "ride", false],
	["hills_evening", 186.0, 19.2, "ride", false],
	["mountains_day", 330.0, 12.0, "walk", false],
	["night", 60.0, 23.0, "ride", false],
	["dawn", 250.0, 6.4, "ride", false],
	["sitting", 40.0, 16.0, "sit", false],
	["shop", -1.0, 11.0, "shop", false],
	["mini", 120.0, 17.0, "ride", true],
]

var game
var out_dir := "shots"
var _i := -1
var _wait := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	set_meta("no_save", true)
	root.size = Vector2i(1280, 720)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var name: String = SHOTS[_i][0]
			root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
			print("saved %s/%s.png" % [out_dir, name])
		return false
	_i += 1
	if _i >= SHOTS.size():
		quit()
		return false
	_setup(SHOTS[_i])
	_wait = 40
	return false


func _setup(s: Array) -> void:
	var sim = game.sim
	game.sim_running = false
	sim.sitting = false
	sim.walking = false
	sim.resting_s = 0.0
	var km: float = s[1]
	if s[3] == "shop":
		km = sim.terrain.next_shop_after(20.0)
		sim.coins = 120.0
		sim.resting_s = 300.0
		sim.rest_reason = "shop"
	sim.distance_km = km
	sim.next_shop_km = sim.terrain.next_shop_after(km)
	sim.time_s = (float(s[2]) - float(sim.t.start_hour)) * 3600.0
	sim.speed_ms = 7.0
	sim.cadence_rpm = 88.0
	sim.power_w = 150.0
	sim.intensity = 0.7
	if s[3] == "walk":
		sim.walking = true
		sim.glycogen_g = 30.0
	elif s[3] == "sit":
		sim.sitting = true
		sim.sit_reason = "dehydration"
		sim.water_deficit_l = 4.4
	if s[4] != game.mini:
		game.mini = s[4]
		game.hud.set_mini(s[4])
		root.size = Vector2i(480, 300) if s[4] else Vector2i(1280, 720)
		root.content_scale_size = Vector2i(480, 300) if s[4] else Vector2i(960, 540)
	game.hud.refresh()
