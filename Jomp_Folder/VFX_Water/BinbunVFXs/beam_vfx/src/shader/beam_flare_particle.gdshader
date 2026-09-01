shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

group_uniforms Noise;
uniform sampler2D noise_texture;
uniform float noise_twist = 3.0;
uniform vec2 scroll_speed = vec2(0.0, 1.0);
uniform float beam_length = 4.0;

group_uniforms Color;
uniform vec3 secondary_color : source_color = vec3(0.58, 0.88, 0.98);
uniform vec3 tertiary_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float emission : hint_range(0.0, 10.0, 0.01) = 3.0;
uniform bool is_tertiary = false;

group_uniforms MeshOrientation;
uniform vec3 mesh_scale = vec3(1.0, -1.0, -1.0);
uniform float offset_y = 0.0;

group_uniforms ParticleAnimation;
uniform bool use_particle_lifetime = true;

// Open Amount Animation
uniform float open_amount_start : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float open_amount_end : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float open_time_start : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float open_time_end : hint_range(0.0, 1.0, 0.01) = 0.67;

// Top Pinch Animation (for CylinderMesh cones)
uniform bool pinch_top = false;
uniform float pinch_time_start : hint_range(0.0, 1.0, 0.01) = 0.11;
uniform float pinch_time_end : hint_range(0.0, 1.0, 0.01) = 0.67;

// Flash to White Animation
uniform bool flash_to_white = false;
uniform float flash_time_start : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float flash_time_end : hint_range(0.0, 1.0, 0.01) = 0.67;

// Edge Softness Animation
uniform float edge_softness_start : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_softness_end : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_softness_time_start : hint_range(0.0, 1.0, 0.01) = 0.11;
uniform float edge_softness_time_end : hint_range(0.0, 1.0, 0.01) = 0.67;

// Static Fallbacks if not using particle lifetime
group_uniforms General;
uniform float open_amount : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float speed_scale : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float edge_softness : hint_range(0.0, 1.0, 0.01) = 0.5;

varying float v_progress;

float overlay(float base, float blend){
	float limit = step(0.5, base);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

void vertex(){
	float progress = 0.0;
	if (use_particle_lifetime) {
		progress = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	}
	v_progress = progress;

	// Calculate animated open_amount
	float cur_open_amount = open_amount;
	if (use_particle_lifetime) {
		float open_factor = smoothstep(open_time_start, open_time_end, progress);
		cur_open_amount = mix(open_amount_start, open_amount_end, open_factor);
	}

	// Apply pinch to top of cylinder if enabled
	if (pinch_top && use_particle_lifetime) {
		float pinch_factor = smoothstep(pinch_time_start, pinch_time_end, progress);
		float top_factor = 1.0 - UV.y;
		VERTEX.xz *= mix(1.0, 0.0, top_factor * pinch_factor);
	}

	float closed_offset = 1.0 - abs(UV.y * 4.0 - 1.0);
	closed_offset = pow(closed_offset, 1.0 - closed_offset);
	closed_offset = UV.y * 4.0;
	closed_offset *= (1.0 - cur_open_amount);
	
	VERTEX += (NORMAL * closed_offset);

	// Apply downward orientation and vertical offset
	VERTEX.xyz *= mesh_scale;
	VERTEX.y += offset_y;
	NORMAL.xyz *= sign(mesh_scale);
}

void fragment() {
	float progress = v_progress;

	vec2 uv = UV;
	uv -= vec2(TIME) * scroll_speed * 0.5;
	
	float noise = texture(noise_texture, uv).r;
	
	float value = overlay(1.0 - UV.y * 3.0, noise);
	
	// Dynamic animated color (flash to white if enabled)
	vec3 cur_sec_color = secondary_color;
	vec3 cur_tert_color = tertiary_color;
	if (flash_to_white && use_particle_lifetime) {
		float flash_factor = smoothstep(flash_time_start, flash_time_end, progress);
		cur_sec_color = mix(cur_sec_color, vec3(1.0), flash_factor);
		cur_tert_color = mix(cur_tert_color, vec3(1.0), flash_factor);
	}

	vec3 color = mix(cur_sec_color, cur_tert_color, pow(value, 2.0));
	ALBEDO = vec3(color) * emission;
	
	// Dynamic animated edge softness
	float cur_edge_softness = edge_softness;
	if (use_particle_lifetime) {
		float soft_factor = smoothstep(edge_softness_time_start, edge_softness_time_end, progress);
		cur_edge_softness = mix(edge_softness_start, edge_softness_end, soft_factor);
	}

	float alpha = value;
	alpha = smoothstep(0.7 - (cur_edge_softness * 0.7), 0.7 + (cur_edge_softness * 0.3), alpha);
	
	// Dynamic animated open mask
	float cur_open_amount = open_amount;
	if (use_particle_lifetime) {
		float open_factor = smoothstep(open_time_start, open_time_end, progress);
		cur_open_amount = mix(open_amount_start, open_amount_end, open_factor);
	}

	float open_mask = UV.y * 2.0;
	open_mask = clamp(1.0 - smoothstep(pow(cur_open_amount, 2.0), pow(cur_open_amount, 0.8), open_mask * 1.2), 0.0, 1.0);
	alpha *= open_mask;
	
	ALPHA = alpha;
}
