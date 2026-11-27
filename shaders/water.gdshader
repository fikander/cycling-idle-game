shader_type spatial;
// Flat cel-shaded water with slow moving bands of lighter colour.

uniform vec4 deep : source_color = vec4(0.16, 0.42, 0.62, 1.0);
uniform vec4 light_band : source_color = vec4(0.45, 0.7, 0.85, 1.0);

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = sin(w.x * 0.08 + TIME * 0.6) * sin(w.z * 0.11 - TIME * 0.4);
	ALBEDO = mix(deep.rgb, light_band.rgb, step(0.75, n));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float d = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += mix(0.5, 1.0, step(0.3, d)) * LIGHT_COLOR / PI;
}
