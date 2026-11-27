extends SceneTree
## Runs the real game loop fast (headless is fine) to catch runtime errors
## in chunk streaming, the HUD and the rider while the world scrolls by.
## Run:  godot --headless --path . --script res://tools/playtest.gd -- frames=3000

var game
var frames := 3000
var _n := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("frames="):
			frames = int(a.substr(7))
	set_meta("no_save", true)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	_n += 1
	if _n == 2:
		game.warp = 60.0
	# Behave like a decent player now and then.
	if _n % 200 == 0:
		var sim = game.sim
		sim.apply_best_gear()
		while sim.water_deficit_l > 0.2 and sim.drink():
			pass
		if sim.glycogen_ratio() < 0.6:
			sim.eat_best()
		sim.stop_at_next_shop = sim.pockets.size() < 2 or sim.water_left_l() < 0.6
		if sim.is_at_shop():
			sim.restock_food()
			sim.leave_shop()
		if sim.sitting:
			sim.roadside_help()
	if _n >= frames:
		var sim = game.sim
		print("playtest: %d frames, %.1f km, %d chunks, day hour %.1f, coins %d" % [
			_n, sim.distance_km, game.world.get_child_count(), sim.hour_of_day(), int(sim.coins)])
		quit()
	return false
