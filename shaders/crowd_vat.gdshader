shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

group_uniforms VAT;
uniform sampler2D vat_pos_tex : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm_tex : filter_nearest, repeat_disable;
uniform int vat_tex_width = 1024;
uniform int vat_rows_per_frame = 1;
uniform float vat_fps = 24.0;

group_uniforms Appearance;
uniform sampler2D albedo_blue : source_color, filter_linear_mipmap;
uniform sampler2D albedo_green : source_color, filter_linear_mipmap;
uniform sampler2D albedo_pink : source_color, filter_linear_mipmap;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.11;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.6;
uniform float rim_tint_val : hint_range(0.0, 1.0) = 1.0;

group_uniforms HitReactionMotion;
uniform float hit_bend_strength = 0.42;
uniform float hit_zone_radius = 0.25;
uniform float hit_oscillation_freq = 10.0;

varying flat int v_tex_variant;

vec3 fetch_vat(sampler2D tex, int col, int frame_idx, int row_offset) {
	int y = frame_idx * vat_rows_per_frame + row_offset;
	return texelFetch(tex, ivec2(col, y), 0).rgb;
}

void vertex() {
	int v_idx = int(round(UV2.x));
	int col = v_idx % vat_tex_width;
	int row_offset = v_idx / vat_tex_width;

	float start_frame = INSTANCE_CUSTOM.r;
	float raw_frame_count = INSTANCE_CUSTOM.g;
	float time_param = INSTANCE_CUSTOM.b;
	v_tex_variant = int(round(INSTANCE_CUSTOM.a));

	float abs_frames = max(abs(raw_frame_count), 1.0);
	float t_frames = (TIME + time_param) * vat_fps;
	float local_frame = mod(t_frames, abs_frames);
	int f0 = int(floor(local_frame));
	int f1 = (f0 + 1) % int(abs_frames);
	float frac = fract(local_frame);

	int g_f0 = int(round(start_frame)) + f0;
	int g_f1 = int(round(start_frame)) + f1;

	vec3 pos0 = fetch_vat(vat_pos_tex, col, g_f0, row_offset);
	vec3 pos1 = fetch_vat(vat_pos_tex, col, g_f1, row_offset);
	vec3 nrm0 = fetch_vat(vat_nrm_tex, col, g_f0, row_offset);
	vec3 nrm1 = fetch_vat(vat_nrm_tex, col, g_f1, row_offset);

	vec3 pos = mix(pos0, pos1, frac);
	vec3 nrm = normalize(mix(nrm0, nrm1, frac));

	// Position-based localized hit reaction via COLOR channel (no color flash/tint)
	// COLOR.r = decay, COLOR.g = hit angle, COLOR.b = local hit Y, COLOR.a = local hit X
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
	vec3 col_tex;
	if (v_tex_variant == 1) {
		col_tex = texture(albedo_green, UV).rgb;
	} else if (v_tex_variant == 2) {
		col_tex = texture(albedo_pink, UV).rgb;
	} else {
		col_tex = texture(albedo_blue, UV).rgb;
	}

	ALBEDO = col_tex;
	ROUGHNESS = roughness_val;
	RIM = rim_amount;
	RIM_TINT = rim_tint_val;
}
