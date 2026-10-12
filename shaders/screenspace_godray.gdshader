// Based on GPU Gems 3: Chapter 13. Volumetric Light Scattering as a Post-Process
// Source: https://godotshaders.com/shader/screenspace-godray/
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, blend_add;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

// Normalized [0, 1] UV screen position of the sun, computed by Camera3D.unproject_position()
instance uniform vec2 light_screen_pos = vec2(0.5, 0.5);

// Sun facing intensity multiplier (0.0 when sun is behind camera, 1.0 when looking towards sun)
instance uniform float sun_facing = 1.0;

group_uniforms ray_properties;
uniform int num_samples : hint_range(8, 128, 1) = 32;
uniform float density : hint_range(0.0, 2.0, 0.01) = 0.75;
uniform float weight : hint_range(0.0, 0.2, 0.001) = 0.02;
uniform float decay : hint_range(0.8, 1.0, 0.005) = 0.95;
uniform float exposure : hint_range(0.0, 2.0, 0.05) = 0.5;

uniform float light_fade_start : hint_range(0.0, 1.0, 0.05) = 0.8;
uniform float light_fade_end : hint_range(0.0, 1.0, 0.05) = 1.0;

uniform vec3 ambient_col : source_color = vec3(1.167, 1.182, 0.725);

group_uniforms near_occlusion;
// Toggles fading/blocking rays on nearby objects, NPCs, and enemies
uniform bool enable_near_fade = true;
// Distance in meters where rays are completely blocked (objects closer than this are 100% ray-free)
uniform float near_fade_start : hint_range(0.0, 30.0, 0.1) = 1.5;
// Distance in meters where rays reach full opacity
uniform float near_fade_end : hint_range(0.1, 50.0, 0.1) = 6.0;

float bayer4x4(vec2 uv, vec2 viewport_size) {
	ivec2 p = ivec2(mod(uv * viewport_size, 4.0));
	int index = p.x + p.y * 4;

	float matrix[16] = float[](
		0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
		12.0/16.0, 4.0/16.0, 14.0/16.0,  6.0/16.0,
		3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
		15.0/16.0, 7.0/16.0, 13.0/16.0,  5.0/16.0
	);

	return matrix[index];
}

float sample_depth_value(sampler2D depth_texture, vec2 uv, float default_val) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return default_val;
	}
	return texture(depth_texture, uv).r;
}

float get_linear_depth(vec2 uv, sampler2D depth_texture, mat4 inv_proj) {
	float raw_depth = texture(depth_texture, uv).r;
	// Godot reverse-Z: near=1.0, far/sky=0.0
	if (raw_depth <= 1e-7) {
		return 10000.0; // Sky is infinitely far
	}
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (sun_facing > 0.001) {
		// Calculate near-distance occlusion mask so close characters/objects block the rays
		float depth_mask = 1.0;
		if (enable_near_fade) {
			float linear_dist = get_linear_depth(SCREEN_UV, depth_tex, INV_PROJECTION_MATRIX);
			depth_mask = smoothstep(near_fade_start, near_fade_end, linear_dist);
		}

		// Dither noise using Bayer matrix to smooth out banding
		float noise = bayer4x4(SCREEN_UV, VIEWPORT_SIZE);

		vec2 delta = (SCREEN_UV - light_screen_pos) / float(num_samples) * density;
		vec2 tex_coord = SCREEN_UV + delta * noise;

		vec3 color = vec3(0.0);
		float illumination_decay = 1.0;

		for (int i = 0; i < num_samples; i++) {
			tex_coord -= delta;

			// Builtin function returns any value outside screen as 0.0 (sky).
			// For this we want any value outside screen as being occluded, so default to 1.0.
			float scene_depth = sample_depth_value(depth_tex, tex_coord, 1.0);

			// Godot reversed Z:
			// near = 1.0
			// far / sky = 0.0
			// Occlusion = 0 when depth > 1e-10 using inverted step function, otherwise occlusion = 1
			float occlusion = 1.0 - step(1e-10, scene_depth);

			float t = float(i) / float(num_samples);
			float sample_fade = 1.0 - smoothstep(light_fade_start, light_fade_end, t);

			color += ambient_col * occlusion * illumination_decay * weight * sample_fade;
			illumination_decay *= decay;
		}

		ALBEDO = color * exposure * sun_facing * depth_mask;
	} else {
		ALBEDO = vec3(0.0);
	}
}
