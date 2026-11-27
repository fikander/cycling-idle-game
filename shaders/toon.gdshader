shader_type spatial;
// Cel shading: light falls into three flat bands with a soft edge,
// shadows get a cool tint, and a thin rim light picks out silhouettes.

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.2;
uniform float band_softness : hint_range(0.001, 0.2) = 0.03;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Bands come from the surface angle; cast shadows darken separately so
	// shadow-map noise never lands right on a band edge.
	float d = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = mix(0.3, 0.7, smoothstep(0.1 - band_softness, 0.1 + band_softness, d));
	band = mix(band, 1.0, smoothstep(0.42 - band_softness, 0.42 + band_softness, d));
	float shadow = mix(0.45, 1.0, smoothstep(0.3, 0.7, ATTENUATION));
	DIFFUSE_LIGHT += band * shadow * LIGHT_COLOR / PI;
	float rim = smoothstep(0.62, 0.68, 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	DIFFUSE_LIGHT += rim * rim_strength * d * LIGHT_COLOR / PI;
}
