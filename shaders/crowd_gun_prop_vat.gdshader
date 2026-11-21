shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

group_uniforms VAT;
uniform sampler2D vat_pos_tex : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm_tex : filter_nearest, repeat_disable;
uniform int vat_tex_width = 1024;
uniform int vat_rows_per_frame = 1;
uniform float vat_fps = 24.0;
uniform float vat_time_override = -1.0;

group_uniforms Appearance;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.05;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.6;
uniform float rim_tint_val : hint_range(0.0, 1.0) = 0.8;

group_uniforms HitReactionMotion;
uniform float hit_bend_strength = 0.42;
uniform float hit_zone_radius = 0.25;
uniform float hit_oscillation_freq = 10.0;

vec3 fetch_vat(sampler2D tex, int col, int frame_idx, int row_offset) {
	int y = frame_idx * vat_rows_per_frame + row_offset;
	return texelFetch(tex, ivec2(col, y), 0).rgb;
}

void sample_vat_frame(int col, int row_offset, float frame_f, out vec3 out_pos, out vec3 out_nrm) {
	int f0 = int(floor(frame_f));
	int f1 = f0 + 1;
	float frac = fract(frame_f);
	vec3 p0 = fetch_vat(vat_pos_tex, col, f0, row_offset);
	vec3 p1 = fetch_vat(vat_pos_tex, col, f1, row_offset);
	vec3 n0 = fetch_vat(vat_nrm_tex, col, f0, row_offset);
	vec3 n1 = fetch_vat(vat_nrm_tex, col, f1, row_offset);
	out_pos = mix(p0, p1, frac);
	out_nrm = normalize(mix(n0, n1, frac));
}

void vertex() {
	int v_idx = int(round(UV2.x));
	int col = v_idx % vat_tex_width;
	int row_offset = v_idx / vat_tex_width;

	float c_r = INSTANCE_CUSTOM.r;
	float c_g = INSTANCE_CUSTOM.g;
	float c_b = INSTANCE_CUSTOM.b;

	vec3 pos;
	vec3 nrm;

	if (c_g >= 0.0) {
		float abs_frames = max(c_g, 1.0);
		float cur_time = vat_time_override >= 0.0 ? vat_time_override : TIME;
		float t_frames = (cur_time + c_b) * vat_fps;
		float local_frame = mod(t_frames, abs_frames);
		int f0 = int(floor(local_frame));
		int f1 = (f0 + 1) % int(abs_frames);
		float frac = fract(local_frame);

		int g_f0 = int(round(c_r)) + f0;
		int g_f1 = int(round(c_r)) + f1;

		vec3 pos0 = fetch_vat(vat_pos_tex, col, g_f0, row_offset);
		vec3 pos1 = fetch_vat(vat_pos_tex, col, g_f1, row_offset);
		vec3 nrm0 = fetch_vat(vat_nrm_tex, col, g_f0, row_offset);
		vec3 nrm1 = fetch_vat(vat_nrm_tex, col, g_f1, row_offset);

		pos = mix(pos0, pos1, frac);
		nrm = normalize(mix(nrm0, nrm1, frac));
	} else {
		vec3 posA;
		vec3 nrmA;
		sample_vat_frame(col, row_offset, max(c_r, 0.0), posA, nrmA);

		float blend_w = clamp(c_b, 0.0, 1.0);
		if (blend_w < 0.999) {
			float frameB = max(abs(c_g) - 1.0, 0.0);
			vec3 posB;
			vec3 nrmB;
			sample_vat_frame(col, row_offset, frameB, posB, nrmB);
			pos = mix(posB, posA, blend_w);
			nrm = normalize(mix(nrmB, nrmA, blend_w));
		} else {
			pos = posA;
			nrm = nrmA;
		}
	}

	// Match parent body's localized hit reaction so the gun stays locked in hand when hit!
	float hit_decay = COLOR.r;
	if (hit_decay > 0.001) {
		float angle = COLOR.g * 6.2831853;
		vec2 hit_dir_xz = vec2(cos(angle), sin(angle));
		vec2 hit_center_xy = vec2((COLOR.a - 0.5) * 2.0, COLOR.b * 1.8);

		float wave = sin(hit_decay * hit_oscillation_freq) * hit_decay;

		vec2 d_xy = pos.xy - hit_center_xy;
		float zone_weight = exp(-dot(d_xy, d_xy) / max(hit_zone_radius * hit_zone_radius, 0.01));
		float floor_anchor = smoothstep(0.04, 0.22, pos.y);
		float follow_through = 0.22 * smoothstep(0.25, 1.5, pos.y);

		pos.xz += hit_dir_xz * (wave * hit_bend_strength * floor_anchor * (zone_weight + follow_through));
	}

	VERTEX = pos;
	NORMAL = nrm;
}

void fragment() {
	ALBEDO = texture(palette_tex, UV).rgb;
	ROUGHNESS = roughness_val;
	RIM = rim_amount;
	RIM_TINT = rim_tint_val;
}
