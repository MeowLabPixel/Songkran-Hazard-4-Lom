shader_type spatial;
render_mode cull_disabled, unshaded;

group_uniforms VAT;
uniform sampler2D vat_pos_tex : filter_nearest, repeat_disable;
uniform int vat_tex_width = 1024;
uniform int vat_rows_per_frame = 1;
uniform float vat_fps = 24.0;
uniform float vat_time_override = -1.0;

group_uniforms HitReactionMotion;
uniform float hit_bend_strength = 0.42;
uniform float hit_zone_radius = 0.25;
uniform float hit_oscillation_freq = 10.0;

group_uniforms DistanceLOD;
uniform bool use_lod_fade = false;
uniform bool keep_front_row_shadow = true;
uniform vec3 lod_ref_pos = vec3(0.0);
uniform float shadow_fade_start = 20.0;
uniform float shadow_fade_end = 30.0;
uniform float max_render_fade_start = 95.0;
uniform float max_render_fade_end = 110.0;

varying float v_shadow_fade;

vec3 fetch_pos(int col, int frame_idx, int row_offset) {
	int y = frame_idx * vat_rows_per_frame + row_offset;
	return texelFetch(vat_pos_tex, ivec2(col, y), 0).rgb;
}

vec3 sample_pos_frame(int col, int row_offset, float frame_f) {
	int f0 = int(floor(frame_f));
	int f1 = f0 + 1;
	float frac = fract(frame_f);
	return mix(fetch_pos(col, f0, row_offset), fetch_pos(col, f1, row_offset), frac);
}

void vertex() {
	float fade = 1.0;
	if (use_lod_fade) {
		vec3 inst_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float dist = length(inst_world - lod_ref_pos);
		bool is_front = INSTANCE_CUSTOM.a >= 5.0;
		if (keep_front_row_shadow && is_front) {
			fade = 1.0 - smoothstep(max_render_fade_start, max_render_fade_end, dist);
		} else {
			fade = 1.0 - smoothstep(shadow_fade_start, shadow_fade_end, dist);
		}
	}

	v_shadow_fade = clamp(fade, 0.0, 1.0);
	if (v_shadow_fade <= 0.001) {
		VERTEX = vec3(0.0);
	} else {
		int v_idx = int(round(UV2.x));
		int col = v_idx % vat_tex_width;
		int row_offset = v_idx / vat_tex_width;

		float c_r = INSTANCE_CUSTOM.r;
		float c_g = INSTANCE_CUSTOM.g;
		float c_b = INSTANCE_CUSTOM.b;

		vec3 pos;
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
			pos = mix(fetch_pos(col, g_f0, row_offset), fetch_pos(col, g_f1, row_offset), frac);
		} else {
			vec3 posA = sample_pos_frame(col, row_offset, max(c_r, 0.0));
			float blend_w = clamp(c_b, 0.0, 1.0);
			if (blend_w < 0.999) {
				float frameB = max(abs(c_g) - 1.0, 0.0);
				vec3 posB = sample_pos_frame(col, row_offset, frameB);
				pos = mix(posB, posA, blend_w);
			} else {
				pos = posA;
			}
		}

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
	}
}

void fragment() {
	if (v_shadow_fade <= 0.001) {
		discard;
	}
	if (v_shadow_fade < 0.999) {
		// 4x4 Bayer ordered dither blurred by DirectionalLight PCF into a smooth shadow fade
		int px = int(FRAGCOORD.x) % 4;
		int py = int(FRAGCOORD.y) % 4;
		int idx = py * 4 + px;
		float bayer = 0.0;
		if (idx == 0) bayer = 0.0625;
		else if (idx == 1) bayer = 0.5625;
		else if (idx == 2) bayer = 0.1875;
		else if (idx == 3) bayer = 0.6875;
		else if (idx == 4) bayer = 0.8125;
		else if (idx == 5) bayer = 0.3125;
		else if (idx == 6) bayer = 0.9375;
		else if (idx == 7) bayer = 0.4375;
		else if (idx == 8) bayer = 0.2500;
		else if (idx == 9) bayer = 0.7500;
		else if (idx == 10) bayer = 0.1250;
		else if (idx == 11) bayer = 0.6250;
		else if (idx == 12) bayer = 1.0000;
		else if (idx == 13) bayer = 0.5000;
		else if (idx == 14) bayer = 0.8750;
		else bayer = 0.3750;
		if (v_shadow_fade < bayer) {
			discard;
		}
	}
	ALBEDO = vec3(0.0);
}
