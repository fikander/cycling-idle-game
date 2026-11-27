extends RefCounted
## Pure functions for cycling physics. No game state lives here.
##
## Power balance at steady speed v on a slope with grade g:
##   P = (rolling + gravity + aero) * v / drivetrain_efficiency
## where rolling = Crr * m * g * cos(a), gravity = m * g * sin(a),
## aero = 0.5 * rho * CdA * v^2.


static func power_for_speed(v: float, grade: float, mass: float, p: Dictionary) -> float:
	var angle := atan(grade)
	var gr: float = p.gravity
	var rolling: float = p.crr * mass * gr * cos(angle)
	var climbing: float = mass * gr * sin(angle)
	var aero: float = 0.5 * p.air_density * p.cda * v * v
	return (rolling + climbing + aero) * v / p.drivetrain_efficiency


## Speed (m/s) the rider holds with a given power. Solved by bisection,
## since power_for_speed is monotonic in v once v is above the coasting speed.
static func speed_for_power(power: float, grade: float, mass: float, p: Dictionary) -> float:
	var lo := 0.0
	var hi := 40.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if power_for_speed(mid, grade, mass, p) > power:
			hi = mid
		else:
			lo = mid
	return lo


## Speed at which the rider rolls without pedalling. Zero on climbs and flats.
static func coasting_speed(grade: float, mass: float, p: Dictionary) -> float:
	if power_for_speed(0.5, grade, mass, p) >= 0.0:
		return 0.0
	return min(speed_for_power(0.0, grade, mass, p), p.max_descent_speed_ms)


## Speed in m/s for a cadence (rpm) and gear (teeth).
static func gear_speed(cadence_rpm: float, chainring: int, cog: int, circumference_m: float) -> float:
	return cadence_rpm / 60.0 * (float(chainring) / float(cog)) * circumference_m


## Cadence in rpm needed to move at speed v in a gear.
static func cadence_for_speed(v: float, chainring: int, cog: int, circumference_m: float) -> float:
	return v / circumference_m / (float(chainring) / float(cog)) * 60.0


## Piecewise linear lookup in a list of [x, y] pairs sorted by x.
static func curve(points: Array, x: float) -> float:
	if x <= points[0][0]:
		return points[0][1]
	for i in range(1, points.size()):
		if x <= points[i][0]:
			var a: Array = points[i - 1]
			var b: Array = points[i]
			var t: float = (x - a[0]) / (b[0] - a[0])
			return lerpf(a[1], b[1], t)
	return points[-1][1]
