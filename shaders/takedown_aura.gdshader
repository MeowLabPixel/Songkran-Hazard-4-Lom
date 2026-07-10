shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

uniform vec4 pink_color : source_color = vec4(1.0, 0.07, 0.57, 1.0); // Hot pink (#FF1292)
uniform vec4 blue_color : source_color = vec4(0.0, 0.75, 1.0, 1.0);  // Cyan/Light Blue (#00C0FF)
uniform float aura_speed : hint_range(0.1, 10.0) = 3.0;
uniform float aura_flicker : hint_range(0.0, 1.0) = 0.25;
uniform float aura_scale : hint_range(0.0, 0.2) = 0.04; // how much it expands along normals
uniform float alpha_val : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	float speed = TIME * aura_speed;
	
	// Create organic undulating waves along the mesh normals
	float wave_x = sin(VERTEX.y * 6.0 - speed * 1.5) * cos(VERTEX.z * 4.0 + speed);
	float wave_y = cos(VERTEX.x * 5.0 + speed) * sin(VERTEX.z * 5.0 - speed * 1.2);
	float undulation = (wave_x + wave_y) * 0.02;
	
	// Taper displacement slightly at the very top of the character
	float height_taper = clamp(1.0 - (VERTEX.y - 1.0) * 0.3, 0.3, 1.0);
	float displacement = (aura_scale + undulation) * height_taper;
	
	VERTEX += NORMAL * displacement;
	
	// Apply rising heat sway to simulate wind/heat-haze moving the flame tongues
	VERTEX.x += sin(speed * 1.2 + VERTEX.y * 3.0) * 0.015 * height_taper;
	VERTEX.z += cos(speed * 1.0 + VERTEX.y * 3.0) * 0.015 * height_taper;
}

void fragment() {
	float speed = TIME * aura_speed;
	vec3 pos = VERTEX;
	
	// Layered 3D sine-based noise to simulate rising tongues of fire
	float wave1 = sin(pos.x * 4.0) * cos(pos.y * 3.0 - speed * 1.5) * sin(pos.z * 4.0);
	float wave2 = sin(pos.x * 8.0 + speed * 0.5) * cos(pos.y * 6.0 - speed * 2.2) * sin(pos.z * 8.0) * 0.5;
	float wave3 = sin(pos.x * 2.0 - speed * 0.5) * cos(pos.y * 1.5 - speed * 0.8) * sin(pos.z * 2.0) * 0.25;
	
	float combined = (wave1 + wave2 + wave3) / 1.75; // Normalized to [-1, 1]
	float flame = combined * 0.5 + 0.5; // Map to [0, 1]
	
	// Sharpen the noise to form distinct tongues of flame
	float flame_tongues = smoothstep(0.3, 0.7, flame);
	
	// Taper the flames as they go above the head/torso (starts tapering around 0.8m)
	float taper = clamp(1.0 - (pos.y - 0.8) * 0.8, 0.0, 1.0);
	
	// Dynamic flicker
	float flicker = 1.0 - (sin(TIME * 25.0) * cos(TIME * 18.0) * aura_flicker);
	
	// Alpha is determined by the flame tongues, vertical taper, and flicker
	float alpha_glow = flame_tongues * taper * flicker;
	
	// Complex color mix: Pink inside the hotter cores, Blue at the outer edges and cooler tops
	float core_mix = clamp(flame_tongues * 1.5 - 0.2, 0.0, 1.0);
	float height_mix = clamp((pos.y + 0.2) / 1.8, 0.0, 1.0);
	float blend_factor = clamp(core_mix * 0.65 + (1.0 - height_mix) * 0.35, 0.0, 1.0);
	
	vec4 aura_color = mix(blue_color, pink_color, blend_factor);
	
	ALBEDO = aura_color.rgb;
	ALPHA = clamp(alpha_glow * alpha_val, 0.0, 1.0);
}
