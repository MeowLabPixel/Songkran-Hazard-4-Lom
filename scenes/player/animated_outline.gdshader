shader_type spatial;
render_mode unshaded, depth_draw_never;

stencil_mode write, compare_greater, 30;

// License: CC0
// Author: Ultipuk, https://ultipuk.xyz
// Link: https://godotshaders.com/shader/stencil-clip-shadow

uniform vec3 shadow_color: source_color = vec3(0.0, 0.0, 1.0);
uniform vec2 offset_px = vec2(-12.0, 0.0);

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.xy += offset_px * 2.0 / VIEWPORT_SIZE * POSITION.w;
}

void fragment() {
	ALBEDO = shadow_color;
}