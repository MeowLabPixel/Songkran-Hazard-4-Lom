shader_type spatial;
render_mode cull_front, unshaded;

group_uniforms Outline;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.6); // #ffffff99
uniform float outline_thickness = 0.006;

group_uniforms HitReactionMotion;
uniform float hit_bend_strength = 0.42;
uniform float hit_zone_radius = 0.25;
uniform float hit_oscillation_freq = 10.0;

instance uniform vec4 hit_data = vec4(0.0, 0.0, 0.5, 0.5);

void vertex() {
	float hit_decay = hit_data.r;
	if (hit_decay > 0.001) {
		float angle = hit_data.g * 6.2831853;
		vec2 hit_dir_xz = vec2(cos(angle), sin(angle));
		vec2 hit_center_xy = vec2((hit_data.a - 0.5) * 2.0, hit_data.b * 1.8);

		float wave = sin(hit_decay * hit_oscillation_freq) * hit_decay;

		vec2 d_xy = VERTEX.xy - hit_center_xy;
		float zone_weight = exp(-dot(d_xy, d_xy) / max(hit_zone_radius * hit_zone_radius, 0.01));
		float floor_anchor = smoothstep(0.04, 0.22, VERTEX.y);
		float follow_through = 0.22 * smoothstep(0.25, 1.5, VERTEX.y);

		VERTEX.xz += hit_dir_xz * (wave * hit_bend_strength * floor_anchor * (zone_weight + follow_through));
	}

	VERTEX += NORMAL * outline_thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
