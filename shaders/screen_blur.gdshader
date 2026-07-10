shader_type canvas_item;

uniform float lod: hint_range(0.0, 5.0) = 2.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 color = textureLod(screen_texture, SCREEN_UV, lod);
	color.rgb = mix(color.rgb, vec3(0.02, 0.02, 0.03), 0.45);
	COLOR = color;
}
