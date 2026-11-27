shader_type spatial;
// Inverted-hull outline: the mesh is drawn again, slightly inflated,
// showing only its back faces in a flat dark colour.
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.12, 0.1, 0.14, 1.0);
uniform float width = 0.025;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
