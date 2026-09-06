shader_type canvas_item;

uniform float softness : hint_range(0.0, 0.1) = 0.02;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float alpha = 1.0 - smoothstep(1.0 - softness, 1.0, dist);
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= alpha;
}
