extends RefCounted
## Endless, seeded road profile. Everything is a pure function of distance,
## so the renderer and the simulation always agree on the road.

var cfg: Dictionary
var biomes: Array
var _noise_a := FastNoiseLite.new()
var _noise_b := FastNoiseLite.new()
var _seed: int


func _init(terrain_cfg: Dictionary) -> void:
	cfg = terrain_cfg
	biomes = cfg.biomes
	_seed = int(cfg.seed)
	_noise_a.seed = _seed
	_noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_a.frequency = 1.0
	_noise_b.seed = _seed + 7
	_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_b.frequency = 1.0


## Biome index for a segment. The first segment is always the first biome
## (gentle fields) so new players start easy.
func biome_index_for_segment(segment: int) -> int:
	if segment <= 0:
		return 0
	return absi(hash([_seed, segment])) % biomes.size()


func biome_at(km: float) -> Dictionary:
	return biomes[biome_index_for_segment(int(floor(km / cfg.segment_km)))]


## Blends a biome parameter across segment borders so climbs never jump.
func _blended(km: float, key: String) -> float:
	var seg_len: float = cfg.segment_km
	var seg := int(floor(km / seg_len))
	var into := km - seg * seg_len
	var here: float = biomes[biome_index_for_segment(seg)][key]
	var half: float = cfg.blend_km * 0.5
	if into < half and seg > 0:
		var prev: float = biomes[biome_index_for_segment(seg - 1)][key]
		return lerpf(prev, here, 0.5 + into / cfg.blend_km)
	if into > seg_len - half:
		var nxt: float = biomes[biome_index_for_segment(seg + 1)][key]
		return lerpf(here, nxt, (into - (seg_len - half)) / cfg.blend_km)
	return here


func elevation_m(km: float) -> float:
	var amp := _blended(km, "amp_m")
	var freq := _blended(km, "freq")
	var n := _noise_a.get_noise_1d(km * freq) + 0.35 * _noise_b.get_noise_1d(km * freq * 3.1)
	return amp * n


## Road grade as a fraction (0.05 = 5 %), measured over 100 m.
func grade_at(km: float) -> float:
	var g := (elevation_m(km + 0.05) - elevation_m(km - 0.05)) / 100.0
	return clampf(g, -cfg.get("max_grade", 0.12), cfg.get("max_grade", 0.12))


func temperature_c(km: float, hour_of_day: float) -> float:
	var day := sin((hour_of_day - 9.0) / 24.0 * TAU)
	return cfg.base_temp_c + cfg.day_temp_swing_c * day + _blended(km, "temp_offset_c")


func shop_km(index: int) -> float:
	var jitter: float = (float(absi(hash([_seed, "shop", index])) % 1000) / 1000.0 - 0.5) * 2.0
	return (index + 1) * cfg.shop_every_km + jitter * cfg.shop_jitter_km


## First shop strictly after km.
func next_shop_after(km: float) -> float:
	var i := maxi(0, int(floor(km / cfg.shop_every_km)) - 1)
	while shop_km(i) <= km:
		i += 1
	return shop_km(i)
