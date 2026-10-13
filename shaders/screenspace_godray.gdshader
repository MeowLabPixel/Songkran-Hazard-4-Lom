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
// Maximum screen-space reach of rays (e.g. 0.75 = 75% of screen for sweeping light shafts)
uniform float max_ray_length : hint_range(0.05, 1.5, 0.01) = 0.75;
uniform float density : hint_range(0.0, 2.0, 0.01) = 0.75;
uniform float weight : hint_range(0.0, 0.2, 0.001) = 0.02;
uniform float decay : hint_range(0.7, 1.0, 0.005) = 0.94;
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

// Toggles vertical down-to-up gradient for near occlusion rays
uniform bool enable_near_gradient = true;
// Ray alpha/opacity at the bottom (down) of near rays (0.0 = completely transparent/blocked at bottom)
uniform float near_gradient_bottom_alpha : hint_range(0.0, 1.0, 0.01) = 0.0;
// Ray alpha/opacity at the top (up) of near rays (1.0 = fully opaque at top)
uniform float near_gradient_top_alpha : hint_range(0.0, 1.0, 0.05) = 1.0;
// Vertical screen position (Y) where the bottom fade begins (0.0 = bottom of screen)
uniform float near_gradient_bottom_y : hint_range(0.0, 1.0, 0.05) = 0.1;
// Vertical screen position (Y) where the top opacity is reached (1.0 = top of screen)
uniform float near_gradient_top_y : hint_range(0.0, 1.0, 0.05) = 0.8;
// Exponent to adjust the gradient falloff curve (1.0 = linear, >1.0 = softer bottom, <1.0 = sharper bottom)
uniform float near_gradient_curve : hint_range(0.2, 4.0, 0.1) = 1.0;

group_uniforms distance_blur;
// Toggles distance-based Gaussian blur for godrays
uniform bool enable_depth_blur = true;
// Distance in meters below which godrays remain sharp and crisp
uniform float blur_near_distance : hint_range(0.0, 50.0, 1.0) = 12.0;
// Distance in meters where godrays reach maximum Gaussian blur
uniform float blur_far_distance : hint_range(1.0, 300.0, 5.0) = 70.0;
// Maximum screen-space spread of the Gaussian blur
uniform float max_blur_radius : hint_range(0.0, 0.05, 0.001) = 0.015;

group_uniforms atmospheric_animation;
// Toggles dynamic atmospheric animation and world-anchoring
uniform bool enable_animation = true;
// Speed of the atmospheric drift and ray breathing
uniform float animation_speed : hint_range(0.0, 3.0, 0.05) = 0.6;
// Frequency / scale of the light shafts (lower = broader beams, higher = finer streams)
uniform float animation_scale : hint_range(1.0, 20.0, 0.5) = 6.0;
// Intensity of the animation modulation (0.0 = static rays, 0.20 = natural organic drift)
uniform float animation_intensity : hint_range(0.0, 0.6, 0.02) = 0.20;
// Angular blur radius to soften and diffuse the animated light shafts (0.0 = crisp distinct beams, 0.3+ = soft hazy glow)
uniform float animation_blur_radius : hint_range(0.0, 0.5, 0.01) = 0.15;

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

float linearize_depth(float raw_depth, vec2 uv, mat4 inv_proj) {
	// Godot reverse-Z: near=1.0, far/sky=0.0
	if (raw_depth <= 1e-7) {
		return 10000.0; // Sky is infinitely far
	}
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

// Clever depth detector: reads geometry depth directly, or probes along ray direction for sky silhouettes
float detect_godray_depth(vec2 uv, vec2 ray_dir, mat4 inv_proj) {
	float raw_depth = texture(depth_tex, uv).r;
	if (raw_depth > 1e-7) {
		return linearize_depth(raw_depth, uv, inv_proj);
	}

	// For sky pixels: probe slightly backwards along the ray (away from the sun towards the occluders)
	vec2 probe_dir = -ray_dir;
	float d1 = sample_depth_value(depth_tex, uv + probe_dir * 0.015, 0.0);
	if (d1 > 1e-7) return linearize_depth(d1, uv + probe_dir * 0.015, inv_proj);

	float d2 = sample_depth_value(depth_tex, uv + probe_dir * 0.040, 0.0);
	if (d2 > 1e-7) return linearize_depth(d2, uv + probe_dir * 0.040, inv_proj);

	float d3 = sample_depth_value(depth_tex, uv + probe_dir * 0.080, 0.0);
	if (d3 > 1e-7) return linearize_depth(d3, uv + probe_dir * 0.080, inv_proj);

	// High open sky with no nearby silhouettes: fake depth based on horizon proximity
	float horizon_dist = clamp(1.0 - abs(uv.y - 0.45) * 2.0, 0.0, 1.0);
	return mix(25.0, 100.0, horizon_dist);
}

// Fast analytical harmonic evaluator for organic atmospheric light beams
float evaluate_anim_harmonic(float angle, float scale, float time_val) {
	float wave1 = sin(angle * scale + time_val);
	float wave2 = cos(angle * (scale * 1.618) - time_val * 0.618);
	return (wave1 + wave2 * 0.5) / 1.5;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (sun_facing > 0.001) {
		float current_pixel_raw_depth = texture(depth_tex, SCREEN_UV).r;
		float current_pixel_dist = linearize_depth(current_pixel_raw_depth, SCREEN_UV, INV_PROJECTION_MATRIX);

		// Calculate near-distance occlusion mask with down-to-up gradient control
		float depth_mask = 1.0;
		if (enable_near_fade) {
			float dist_mask = smoothstep(near_fade_start, near_fade_end, current_pixel_dist);
			if (enable_near_gradient) {
				// 0.0 at bottom (down), 1.0 at top (up)
				float vert_pos = 1.0 - SCREEN_UV.y;
				float vert_t = clamp((vert_pos - near_gradient_bottom_y) / max(near_gradient_top_y - near_gradient_bottom_y, 0.001), 0.0, 1.0);
				float vert_factor = pow(vert_t, near_gradient_curve);
				float gradient_alpha = mix(near_gradient_bottom_alpha, near_gradient_top_alpha, vert_factor);

				// For close objects (dist_mask -> 0), apply gradient_alpha.
				// As distance moves beyond near_fade_end (dist_mask -> 1), blend smoothly to full opacity (1.0).
				depth_mask = mix(gradient_alpha, 1.0, dist_mask);
			} else {
				depth_mask = dist_mask;
			}
		}

		// Direction and distance towards the sun in screen space
		vec2 to_sun = light_screen_pos - SCREEN_UV;
		float dist_to_sun = length(to_sun);
		vec2 ray_dir = to_sun / max(dist_to_sun, 0.0001);

		// Calculate world-anchored atmospheric animation modulation
		float anim_mod = 1.0;
		if (enable_animation) {
			// World-space orientation anchor: camera world yaw angle from INV_VIEW_MATRIX
			float camera_yaw = atan(INV_VIEW_MATRIX[0].z, INV_VIEW_MATRIX[0].x);

			// Angular coordinate of the ray relative to the sun
			float ray_angle = atan(to_sun.y, to_sun.x);

			// Anchors the light beams to the 3D world as camera rotates
			float world_angle = ray_angle + camera_yaw;

			float time_val = TIME * animation_speed;
			float harmonic;
			if (animation_blur_radius > 0.001) {
				// 3-tap analytical angular Gaussian blur (weights: 0.442 center, 0.279 sides)
				float h_center = evaluate_anim_harmonic(world_angle, animation_scale, time_val);
				float h_pos = evaluate_anim_harmonic(world_angle + animation_blur_radius, animation_scale, time_val);
				float h_neg = evaluate_anim_harmonic(world_angle - animation_blur_radius, animation_scale, time_val);
				harmonic = h_center * 0.442 + (h_pos + h_neg) * 0.279;
			} else {
				harmonic = evaluate_anim_harmonic(world_angle, animation_scale, time_val);
			}

			anim_mod = 1.0 + harmonic * animation_intensity;
		}

		// Clamp the total ray reach
		float march_dist = min(dist_to_sun * density, max_ray_length);

		// Detect / fake depth for this godray to determine blur amount
		float detected_depth = detect_godray_depth(SCREEN_UV, ray_dir, INV_PROJECTION_MATRIX);
		float blur_factor = 0.0;
		if (enable_depth_blur) {
			blur_factor = smoothstep(blur_near_distance, blur_far_distance, detected_depth);
		}
		float current_blur_radius = blur_factor * max_blur_radius;

		// Vector perpendicular to ray direction for cross-ray Gaussian blur
		vec2 perp_dir = vec2(-ray_dir.y, ray_dir.x);

		// Dither noise using Bayer matrix to smooth out banding
		float noise = bayer4x4(SCREEN_UV, VIEWPORT_SIZE);

		// Raymarching step vector towards the sun
		vec2 delta = (ray_dir * march_dist) / float(num_samples);
		vec2 tex_coord = SCREEN_UV + delta * noise;

		vec3 color = vec3(0.0);
		float illumination_decay = 1.0;

		for (int i = 0; i < num_samples; i++) {
			tex_coord += delta;

			float t = float(i) / float(num_samples);
			float occlusion;

			if (current_blur_radius > 0.0001) {
				// Scale blur slightly along ray progression for natural volumetric dispersion
				vec2 blur_offset = perp_dir * (current_blur_radius * (0.6 + 0.4 * t));

				// 3-tap analytical Gaussian kernel (weights: 0.442 center, 0.279 sides)
				float scene_depth_center = sample_depth_value(depth_tex, tex_coord, 1.0);
				float scene_depth_pos = sample_depth_value(depth_tex, tex_coord + blur_offset, 1.0);
				float scene_depth_neg = sample_depth_value(depth_tex, tex_coord - blur_offset, 1.0);

				float occ_center = 1.0 - step(1e-10, scene_depth_center);
				float occ_pos = 1.0 - step(1e-10, scene_depth_pos);
				float occ_neg = 1.0 - step(1e-10, scene_depth_neg);

				occlusion = occ_center * 0.442 + (occ_pos + occ_neg) * 0.279;
			} else {
				float scene_depth = sample_depth_value(depth_tex, tex_coord, 1.0);
				occlusion = 1.0 - step(1e-10, scene_depth);
			}

			float sample_fade = 1.0 - smoothstep(light_fade_start, light_fade_end, t);

			color += ambient_col * occlusion * illumination_decay * weight * sample_fade;
			illumination_decay *= decay;
		}

		ALBEDO = color * exposure * sun_facing * depth_mask * anim_mod;
	} else {
		ALBEDO = vec3(0.0);
	}
}
