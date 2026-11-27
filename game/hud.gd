extends CanvasLayer
## On-screen interface, built in code. Reads the simulation every few frames
## and calls straight into it for player actions.

var game  # game.gd
var sim

var _root: Control
var _top: PanelContainer
var _left: PanelContainer
var _bottom: PanelContainer
var _mini_panel: PanelContainer
var _toasts: VBoxContainer
var _shop_panel: PanelContainer
var _sit_panel: PanelContainer
var _away_panel: PanelContainer
var _finish_panel: PanelContainer

var _labels := {}
var _bars := {}
var _pocket_box: HBoxContainer
var _pockets_shown := []
var _shop_food_box: VBoxContainer
var _shop_upgrade_box: VBoxContainer
var _shop_title: Label
var _away_label: Label
var _sit_label: Label
var _help_button: Button
var _shop_toggle: Button
var _front_button: Button
var _mini_button: Button
var _mini_full: Button
var _refresh_timer := 0.0
var _shop_dirty := true
var mini := false

const C_PANEL := Color(0.08, 0.09, 0.13, 0.78)
const C_ENERGY := Color("f2a33a")
const C_GUT := Color("d9c27a")
const C_WATER := Color("49a8e8")
const C_HYDRATION := Color("6fd0f0")
const C_FATIGUE := Color("b986e0")
const C_LEGS := Color("e07a9a")


func setup(g) -> void:
	game = g
	sim = g.sim
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_top()
	_build_left()
	_build_bottom()
	_build_mini()
	_build_toasts()
	_build_shop()
	_build_sitting()
	_build_away()
	_build_finish()
	set_mini(false)
	refresh()


# ---------------------------------------------------------------- building

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 17
	var panel := StyleBoxFlat.new()
	panel.bg_color = C_PANEL
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(8)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		match state:
			"normal": sb.bg_color = Color("2d3446")
			"hover": sb.bg_color = Color("3b4560")
			"pressed": sb.bg_color = Color("e2513d")
			"disabled": sb.bg_color = Color("22252e")
			"focus":
				sb.draw_center = false
				sb.border_color = Color("f5d547")
				sb.set_border_width_all(2)
		th.set_stylebox(state, "Button", sb)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	th.set_color("font_color", "Label", Color("f3f1ea"))
	th.set_constant("separation", "HBoxContainer", 8)
	th.set_constant("separation", "VBoxContainer", 4)
	return th


func _label(key: String, text := "", size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if key != "":
		_labels[key] = l
	return l


func _button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _bar(key: String, color: Color, width := 150.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.001
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	_bars[key] = pb
	return pb


func _bar_row(parent: Control, key: String, title: String, color: Color) -> void:
	var row := HBoxContainer.new()
	var t := _label("", title, 14)
	t.custom_minimum_size.x = 70
	row.add_child(t)
	var bar := _bar(key, color, 110.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(_label(key + "_val", "", 14))
	parent.add_child(row)


func _build_top() -> void:
	_top = PanelContainer.new()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = 10
	_top.offset_right = -10
	_top.offset_top = 10
	_root.add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_top.add_child(row)
	for k in ["distance", "speed", "clock", "coins", "place"]:
		row.add_child(_label(k, "", 18))
	_labels.place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_labels.place.clip_text = true
	_labels.place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_label("warp", "", 15))
	_shop_toggle = _button("", func(): sim.stop_at_next_shop = not sim.stop_at_next_shop, "Stop at the next shop")
	_shop_toggle.toggle_mode = true
	row.add_child(_shop_toggle)
	if game.can_mini():
		_mini_button = _button("Mini", func(): game.toggle_mini(), "Small window in the corner (M)")
		row.add_child(_mini_button)


func _build_left() -> void:
	_left = PanelContainer.new()
	_left.position = Vector2(10, 64)
	_left.theme = _root.theme.duplicate()
	_left.theme.default_font_size = 14
	_root.add_child(_left)
	var v := VBoxContainer.new()
	_left.add_child(v)
	_bar_row(v, "energy", "Energy", C_ENERGY)
	_bar_row(v, "gut", "Stomach", C_GUT)
	_bar_row(v, "water", "Bottles", C_WATER)
	_bar_row(v, "hydration", "Hydration", C_HYDRATION)
	_bar_row(v, "fatigue", "Fatigue", C_FATIGUE)
	_bar_row(v, "legs", "Legs", C_LEGS)
	v.add_child(HSeparator.new())
	_bar_row(v, "effort", "Effort", Color("7ed37a"))
	v.add_child(_label("status", "", 15))
	v.add_child(_label("levels", "", 12))


func _build_bottom() -> void:
	_bottom = PanelContainer.new()
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_left = 10
	_bottom.offset_right = -10
	_bottom.offset_bottom = -10
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bottom.add_child(row)
	_bottom.theme = _root.theme.duplicate()
	_bottom.theme.default_font_size = 15

	var cad := HBoxContainer.new()
	cad.add_child(_button("–", func(): sim.set_cadence(sim.cadence_target - 5.0), "Slower cadence (A)"))
	var cl := _label("cadence", "", 16)
	cl.custom_minimum_size.x = 76
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cad.add_child(cl)
	cad.add_child(_button("+", func(): sim.set_cadence(sim.cadence_target + 5.0), "Faster cadence (D)"))
	cad.set_meta("full_only", true)
	row.add_child(cad)

	var gear := HBoxContainer.new()
	_front_button = _button("", func(): sim.shift_front(1 - sim.front), "Switch chainring (F)")
	_front_button.set_meta("full_only", true)
	gear.add_child(_front_button)
	gear.add_child(_button("◀ Easier", func(): sim.shift(-1), "Easier gear (Q)"))
	var gl := _label("gear", "", 16)
	gl.custom_minimum_size.x = 60
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear.add_child(gl)
	gear.add_child(_button("Harder ▶", func(): sim.shift(1), "Harder gear (E)"))
	row.add_child(gear)

	row.add_child(_button("Drink", func(): game.do_drink(), "Take a sip (W)"))
	_pocket_box = HBoxContainer.new()
	_pocket_box.set_meta("full_only", true)
	row.add_child(_pocket_box)
	var eat := _button("Eat", func(): game.do_eat_best(), "Eat the biggest snack (S)")
	eat.set_meta("mini_only", true)
	row.add_child(eat)

	_mini_full = _button("Full", func(): game.toggle_mini(), "Back to the full window (M)")
	_mini_full.set_meta("mini_only", true)
	row.add_child(_mini_full)


func _build_mini() -> void:
	_mini_panel = PanelContainer.new()
	_mini_panel.position = Vector2(6, 6)
	_root.add_child(_mini_panel)
	var v := VBoxContainer.new()
	_mini_panel.add_child(v)
	v.add_child(_label("mini_line", "", 14))
	var bars := HBoxContainer.new()
	bars.add_child(_bar("mini_energy", C_ENERGY, 60))
	bars.add_child(_bar("mini_hydration", C_HYDRATION, 60))
	bars.add_child(_bar("mini_fatigue", C_FATIGUE, 60))
	v.add_child(bars)
	v.add_child(_label("mini_status", "", 13))


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.position.y = 70
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


## Panels sit near the top so the rider stays visible below them.
func _center_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.offset_top = 64
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.visible = false
	_root.add_child(p)
	return p


func _build_shop() -> void:
	_shop_panel = _center_panel()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	_shop_panel.add_child(v)
	_shop_title = _label("", "", 22)
	v.add_child(_shop_title)
	v.add_child(_label("shop_food_hint", "", 15))
	_shop_food_box = VBoxContainer.new()
	v.add_child(_shop_food_box)
	v.add_child(HSeparator.new())
	v.add_child(_label("", "Upgrades", 18))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_shop_upgrade_box = VBoxContainer.new()
	_shop_upgrade_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_upgrade_box)
	v.add_child(_button("Back on the road", func(): sim.leave_shop()))


func _rebuild_shop() -> void:
	_shop_dirty = false
	for c in _shop_food_box.get_children():
		c.queue_free()
	for c in _shop_upgrade_box.get_children():
		c.queue_free()
	var food_row := HBoxContainer.new()
	_shop_food_box.add_child(food_row)
	for id in sim.t.food:
		var f: Dictionary = sim.t.food[id]
		var b := _button("%s  %dg  ¢%d" % [_food_name(id), f.carbs_g, f.price], func():
			sim.buy_food(id)
			_shop_dirty = true)
		b.disabled = sim.coins < f.price or sim.pockets.size() >= sim.pocket_slots
		food_row.add_child(b)
	for u in sim.available_upgrades():
		var row := HBoxContainer.new()
		var name_l := _label("", "%s — %s" % [u.name, u.desc], 15)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var id: String = u.id
		var b2 := _button("Buy ¢%d" % u.price, func():
			if sim.buy_upgrade(id):
				toast("Bought: %s" % u.name)
			_shop_dirty = true)
		b2.disabled = sim.coins < u.price
		row.add_child(b2)
		_shop_upgrade_box.add_child(row)


func _build_sitting() -> void:
	_sit_panel = _center_panel()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	_sit_panel.add_child(v)
	_sit_label = _label("", "", 17)
	_sit_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_sit_label)
	_help_button = _button("", func(): game.do_roadside_help())
	v.add_child(_help_button)


func _build_away() -> void:
	_away_panel = _center_panel()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	_away_panel.add_child(v)
	v.add_child(_label("", "While you were away", 22))
	_away_label = _label("", "", 16)
	_away_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_away_label)
	v.add_child(_button("Let's ride", func(): _away_panel.visible = false))


func _build_finish() -> void:
	_finish_panel = _center_panel()
	var v := VBoxContainer.new()
	_finish_panel.add_child(v)
	v.add_child(_label("finish", "", 22))
	v.add_child(_button("Start a new crossing", func(): game.new_ride()))


# ---------------------------------------------------------------- updates

func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.1
		refresh()
	for t in _toasts.get_children():
		var life: float = t.get_meta("life") - delta
		t.set_meta("life", life)
		t.modulate.a = clampf(life, 0.0, 1.0)
		if life <= 0.0:
			t.queue_free()


func refresh() -> void:
	var day := int(sim.time_s / 86400.0 + sim.t.start_hour / 24.0) + 1
	var hour: float = sim.hour_of_day()
	var biome: String = sim.terrain.biome_at(sim.distance_km).id
	_labels.distance.text = "%.1f / %.0f km" % [sim.distance_km, sim.route_length_km()]
	_labels.speed.text = "%.1f km/h" % (sim.speed_ms * 3.6)
	_labels.clock.text = "Day %d  %02d:%02d" % [day, int(hour), int(fmod(hour, 1.0) * 60.0)]
	_labels.coins.text = "¢ %d" % int(sim.coins)
	_labels.place.text = "%s · shop in %.1f km" % [biome.capitalize(), sim.next_shop_km - sim.distance_km]
	_labels.warp.text = game.warp_label()

	var e: Dictionary = sim.t.exhaustion
	var gly: float = sim.glycogen_ratio()
	var hyd: float = clampf(1.0 - sim.dehydration_pct() / e.sit_dehydration_pct, 0.0, 1.0)
	var cap_l: float = sim.bottles.size() * sim.bottle_capacity_l
	_set_bar("energy", gly, "%d%%" % int(gly * 100.0))
	_set_bar("gut", sim.gut_g / sim.t.rider.gut_capacity_g, "%dg" % int(sim.gut_g))
	_set_bar("water", sim.water_left_l() / max(cap_l, 0.01), "%.2f L" % sim.water_left_l())
	_set_bar("hydration", hyd, "-%.1f%%" % sim.dehydration_pct())
	_set_bar("fatigue", sim.general_fatigue / 100.0, "%d" % int(sim.general_fatigue))
	_set_bar("legs", sim.muscle_fatigue / 100.0, "%d" % int(sim.muscle_fatigue))
	var eff: float = sim.intensity
	_set_bar("effort", eff / 1.2, "%d W · %d%%" % [int(sim.power_w), int(eff * 100.0)])
	var fill: StyleBoxFlat = _bars.effort.get_theme_stylebox("fill")
	fill.bg_color = Color("7ed37a") if eff < 0.62 else (Color("f2d64a") if eff < 0.8 else Color("ee6a4a"))
	_bars.energy.get_theme_stylebox("fill").bg_color = C_ENERGY if gly > 0.15 else Color("ee4a4a")
	_labels.status.text = status_text()
	var lv: Dictionary = sim.levels
	_labels.levels.text = "Training  End %d · Sta %d · Str %d · Gut %d · Cool %d" % [
		lv.endurance, lv.stamina, lv.strength, lv.gut, lv.cooling]

	_labels.cadence.text = "%d rpm" % int(round(sim.cadence_rpm if sim.grinding else sim.cadence_target))
	_labels.gear.text = "%d×%d" % [sim.chainrings[sim.front], sim.cassette[sim.rear]]
	_front_button.text = "Ring %d" % sim.chainrings[sim.front]
	_shop_toggle.button_pressed = sim.stop_at_next_shop
	_shop_toggle.text = "Stop at shop ✓" if sim.stop_at_next_shop else "Stop at shop"
	_refresh_pockets()

	_labels.mini_line.text = "%.1f km · %.0f km/h · ¢%d" % [sim.distance_km, sim.speed_ms * 3.6, int(sim.coins)]
	_bars.mini_energy.value = gly
	_bars.mini_hydration.value = hyd
	_bars.mini_fatigue.value = sim.general_fatigue / 100.0
	_labels.mini_status.text = status_text()

	var at_shop: bool = sim.is_at_shop()
	if at_shop and not _shop_panel.visible:
		_shop_dirty = true
	_shop_panel.visible = at_shop and not mini
	if _shop_panel.visible:
		_labels.shop_food_hint.text = "Bottles refilled for free. Food (%d of %d slots used):" % [sim.pockets.size(), sim.pocket_slots]
		_shop_title.text = "Shop at km %.0f  ·  ¢%d  ·  leaving in %d min" % [sim.distance_km, int(sim.coins), int(ceil(sim.resting_s / 60.0))]
		if _shop_dirty:
			_rebuild_shop()
	_sit_panel.visible = sim.sitting and not mini and not _away_panel.visible
	if _sit_panel.visible:
		var why := "too dehydrated to go on" if sim.sit_reason == "dehydration" else "completely exhausted"
		_sit_label.text = "Your rider is sitting by the road, %s. Give them a drink and something to eat and they'll get going again." % why
		var price: float = e.help_price
		_help_button.text = "Flag down a car (¢%d)" % int(price) if sim.coins >= price else "Flag down a car (free)"
	_finish_panel.visible = sim.finished
	_left.visible = not mini and not (_shop_panel.visible or _sit_panel.visible or _away_panel.visible or _finish_panel.visible)
	if sim.finished:
		_labels.finish.text = "You crossed the continent! %.0f km in %d days." % [sim.distance_km, day]


func _set_bar(key: String, v: float, text: String) -> void:
	_bars[key].value = clampf(v, 0.0, 1.0)
	if _labels.has(key + "_val"):
		_labels[key + "_val"].text = text


func status_text() -> String:
	if sim.finished:
		return "Finished!"
	if sim.is_at_shop():
		return "At the shop"
	if sim.sitting:
		return "Sitting by the road (%s)" % sim.sit_reason
	if sim.walking:
		return "Walking the bike – shift to an easier gear"
	if sim.glycogen_ratio() < sim.t.energy_penalties.bonk_threshold:
		return "Bonking! Eat something"
	if sim.grinding:
		return "Grinding – try an easier gear"
	if sim.coasting:
		return "Coasting downhill"
	if sim.dehydration_pct() > sim.t.energy_penalties.dehydration_free_pct:
		return "Thirsty"
	return "Riding"


func _refresh_pockets() -> void:
	if _pockets_shown == Array(sim.pockets):
		return
	_pockets_shown = Array(sim.pockets).duplicate()
	for c in _pocket_box.get_children():
		c.queue_free()
	var counts := {}
	for f in sim.pockets:
		counts[f] = counts.get(f, 0) + 1
	for f in counts:
		var id: String = f
		var label := _food_name(id) if counts[f] == 1 else "%s ×%d" % [_food_name(id), counts[f]]
		_pocket_box.add_child(_button(label, func(): game.do_eat(id), "%dg carbs" % sim.t.food[id].carbs_g))
	var free_slots: int = sim.pocket_slots - sim.pockets.size()
	if free_slots > 0:
		var l := _label("", "%d free" % free_slots, 13)
		l.modulate.a = 0.6
		_pocket_box.add_child(l)


func _food_name(id: String) -> String:
	return id.replace("_", " ").capitalize()


func toast(text: String) -> void:
	var p := PanelContainer.new()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15 if mini else 18)
	p.add_child(l)
	p.set_meta("life", 4.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		var first := _toasts.get_child(0)
		_toasts.remove_child(first)
		first.queue_free()


func show_away(real_seconds: float, r: Dictionary) -> void:
	var mins := int(real_seconds / 60.0)
	var away := "%d min" % mins if mins < 120 else "%.1f hours" % (real_seconds / 3600.0)
	var text := "You were away for %s. Your rider covered %.1f km and earned ¢%d." % [away, r.km, int(r.coins)]
	if r.sat_at_km >= 0.0:
		text += "\n\nAt km %.0f they ran out of %s and sat down by the road." % [
			r.sat_at_km, "water" if r.sit_reason == "dehydration" else "strength"]
	if r.finished:
		text += "\n\nThey reached the finish!"
	_away_label.text = text
	_away_panel.visible = true


func set_mini(on: bool) -> void:
	mini = on
	_top.visible = not on
	_left.visible = not on
	_mini_panel.visible = on
	for c in _bottom.get_child(0).get_children():
		if c.has_meta("full_only"):
			c.visible = not on
		if c.has_meta("mini_only"):
			c.visible = on
	_front_button.visible = not on
	_mini_full.visible = on
	_root.theme.default_font_size = 14 if on else 17
	_bottom.theme.default_font_size = 14 if on else 15
	_shop_dirty = true
	refresh()
