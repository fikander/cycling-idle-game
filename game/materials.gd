extends RefCounted
## Shared cel-shaded materials, cached by colour so the whole world uses a
## handful of material instances.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const WATER := preload("res://shaders/water.gdshader")

static var _cache := {}


## Flat colour toon material, optionally with an outline pass.
static func toon(color: Color, outline_width := 0.0) -> ShaderMaterial:
	var key := "t%s_%s" % [color.to_html(), outline_width]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	if outline_width > 0.0:
		m.next_pass = _outline(outline_width)
	_cache[key] = m
	return m


## Toon material that takes its colour from the mesh's vertex colours.
static func toon_vertex(outline_width := 0.0) -> ShaderMaterial:
	var key := "v_%s" % outline_width
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("rim_strength", 0.1)
	m.set_shader_parameter("band_softness", 0.08)
	if outline_width > 0.0:
		m.next_pass = _outline(outline_width)
	_cache[key] = m
	return m


static func water() -> ShaderMaterial:
	if not _cache.has("water"):
		var m := ShaderMaterial.new()
		m.shader = WATER
		_cache["water"] = m
	return _cache["water"]


static func _outline(width: float) -> ShaderMaterial:
	var key := "o_%s" % width
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = OUTLINE
		m.set_shader_parameter("width", width)
		_cache[key] = m
	return _cache[key]
